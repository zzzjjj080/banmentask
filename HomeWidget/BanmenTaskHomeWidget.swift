import WidgetKit
import SwiftUI
import AppIntents
import EventKit

// MARK: - データ

struct HomeEntry: TimelineEntry {
    let date: Date
    let listName: String
    let items: [HomeItem]
    let layout: FaceLayout
}

struct HomeItem: Identifiable {
    let id: String
    let title: String
    let deadline: Date?   // ○を押して猶予中なら、完了する時刻
}

/// ウィジェット拡張から直接 EventKit を読む。本体アプリで許可済みなら extension からも読める。
enum HomeReminders {
    static func load(listName: String, limit: Int) -> [HomeItem] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let store = EKEventStore()
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let sem = DispatchSemaphore(value: 0)
        var found: [EKReminder] = []
        store.fetchReminders(matching: predicate) { found = $0 ?? []; sem.signal() }
        _ = sem.wait(timeout: .now() + 5)
        let pending = PendingStore.load()
        return found
            .sorted { a, b in
                let pa = a.priority == 0 ? Int.max : a.priority
                let pb = b.priority == 0 ? Int.max : b.priority
                if pa != pb { return pa < pb }
                return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
            }
            .prefix(limit)
            .map { HomeItem(id: $0.calendarItemIdentifier,
                            title: $0.title ?? "",
                            deadline: pending[$0.calendarItemIdentifier]?.addingTimeInterval(PendingStore.grace)) }
    }

    static func complete(id: String) {
        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    /// 猶予（3秒）を過ぎたものを本当に完了させる。タイムライン生成とインテントの両方から呼ぶ。
    static func settleExpired(now: Date = .now) {
        var pending = PendingStore.load()
        let expired = pending.filter { now.timeIntervalSince($0.value) >= PendingStore.grace }
        guard !expired.isEmpty else { return }
        for id in expired.keys {
            complete(id: id)
            pending[id] = nil
        }
        PendingStore.save(pending)
    }
}

// MARK: - ○を押した時の動き（3秒後に完了。その間にもう一度押せば取り消し）

struct ToggleCompleteIntent: AppIntent {
    static var title: LocalizedStringResource = "完了 / 取り消し"
    static var isDiscoverable = false

    @Parameter(title: "ID") var id: String

    init() {}
    init(id: String) { self.id = id }

    /// ウィジェットはインテントが終わるまで再描画しないので、ここでは待たずに即返す。
    /// 3秒後の再描画（タイムラインの .after）で settleExpired が本当に完了させる。
    func perform() async throws -> some IntentResult {
        HomeReminders.settleExpired()
        var pending = PendingStore.load()
        if pending[id] != nil {
            pending[id] = nil            // 猶予中にもう一度押した → 取り消し
        } else {
            pending[id] = Date.now       // 猶予開始
        }
        PendingStore.save(pending)
        return .result()                 // 返した直後に WidgetKit が再描画する
    }
}

// MARK: - タイムライン

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: .now, listName: "基本",
                  items: [HomeItem(id: "1", title: "洗濯する", deadline: nil),
                          HomeItem(id: "2", title: "電話する", deadline: nil),
                          HomeItem(id: "3", title: "牛乳を買う", deadline: nil)],
                  layout: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(for: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let e = entry(for: context)
        // 猶予中の項目があればその完了時刻で、なければ15分後に読み直す
        let deadlines = e.items.compactMap(\.deadline).filter { $0 > .now }
        let next = deadlines.min().map { $0.addingTimeInterval(0.5) }
            ?? Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry(for context: Context) -> HomeEntry {
        HomeReminders.settleExpired()
        let limit: Int
        switch context.family {
        case .systemLarge: limit = 9
        default: limit = 3           // 正方形（小）と横長（中）は3行
        }
        let listName = LayoutStore.listName
        return HomeEntry(date: .now, listName: listName,
                         items: HomeReminders.load(listName: listName, limit: limit),
                         layout: LayoutStore.load())
    }
}

// MARK: - 見た目（純正リマインダーのウィジェットと同じ作り）

struct HomeWidgetView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private var tint: Color { FaceStyle.color(entry.layout.reminderColor) }
    private var small: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: small ? 2 : 4) {
            HStack {
                Image(systemName: "applewatch")
                    .font(.system(size: 12, weight: .semibold))
                Text(entry.listName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(entry.items.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)

            if entry.items.isEmpty {
                Spacer()
                Text(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ? "タスクなし" : "盤面タスクを一度開いて許可してください")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.items) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.black, for: .widget)
    }

    private func row(_ item: HomeItem) -> some View {
        let waiting = (item.deadline ?? .distantPast) > entry.date
        return HStack(spacing: small ? 6 : 10) {
            Button(intent: ToggleCompleteIntent(id: item.id)) {
                ZStack {
                    Circle().strokeBorder(waiting ? tint : Color(white: 0.45), lineWidth: 1.5)
                    if waiting {
                        Circle().fill(tint)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 20, height: 20)
                .frame(width: 32, height: small ? 28 : 32)   // 当たり判定を広く
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: small ? 14 : 15, weight: .medium))
                .foregroundStyle(waiting ? Color(white: 0.5) : .white)
                .strikethrough(waiting, color: Color(white: 0.5))
                .lineLimit(1)

            Spacer(minLength: 4)

            if waiting, let deadline = item.deadline {
                // 3秒で減るリングと残り秒数。ウィジェットでも動く
                ZStack {
                    ProgressView(timerInterval: deadline.addingTimeInterval(-PendingStore.grace)...deadline,
                                 countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.circular)
                        .tint(tint)
                    Text(timerInterval: entry.date...deadline, countsDown: true, showsHours: false)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
            }
        }
    }
}

// MARK: - 定義

struct BanmenTaskHomeWidget: Widget {
    static let kind = "BanmenTaskHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("盤面タスク")
        .description("リマインダーをホーム画面から完了できます。○を押して3秒以内なら取り消せます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BanmenTaskHomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BanmenTaskHomeWidget()
    }
}

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

    /// 猶予（5秒）を過ぎたものを本当に完了させる。タイムライン生成とインテントの両方から呼ぶ。
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

// MARK: - ○を押した時の動き（5秒後に完了。その間にもう一度押せば取り消し）

struct ToggleCompleteIntent: AppIntent {
    static var title: LocalizedStringResource = "完了 / 取り消し"
    static var isDiscoverable = false

    @Parameter(title: "ID") var id: String

    init() {}
    init(id: String) { self.id = id }

    /// ウィジェットはインテントが終わるまで再描画しないので、ここでは待たずに即返す。
    /// 5秒後の再描画（タイムラインの .after）で settleExpired が本当に完了させる。
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
        let deadlines = e.items.compactMap(\.deadline).filter { $0 > .now }
        guard let last = deadlines.max() else {
            // 猶予中の項目がなければ15分後に読み直す
            completion(Timeline(entries: [e], policy: .after(Calendar.current.date(byAdding: .minute, value: 15, to: .now)!)))
            return
        }
        // 猶予中は1秒ごとの entry を並べて残り秒数を数字で出す（最大でも6枚）
        var entries: [HomeEntry] = [e]
        var t = e.date.addingTimeInterval(1)
        while t < last {
            entries.append(HomeEntry(date: t, listName: e.listName, items: e.items, layout: e.layout))
            t += 1
        }
        completion(Timeline(entries: entries, policy: .after(last.addingTimeInterval(0.5))))
    }

    private func entry(for context: Context) -> HomeEntry {
        HomeReminders.settleExpired()
        // 多めに読んで、表示側が実際に収まる件数まで削る
        let limit: Int
        switch context.family {
        case .systemLarge: limit = 20
        case .systemMedium: limit = 10
        default: limit = 6
        }
        let listName = LayoutStore.listName
        return HomeEntry(date: .now, listName: listName,
                         items: HomeReminders.load(listName: listName, limit: limit),
                         layout: LayoutStore.load())
    }
}

// MARK: - 見た目（純正リマインダーのウィジェットと同じ作り。見出しなし、収まる分だけ表示）

/// 行の寸法。ここだけで決めて、収まる件数の計算と実際の描画の両方で使う。
private enum Metric {
    static let font: CGFloat = 15
    static let lineHeight: CGFloat = 18
    static let circleSlot: CGFloat = 21      // ○ の当たり判定の幅
    static let gap: CGFloat = 5              // ○ と題名のあいだ
    /// 残り秒数の枠。**押していない時も同じだけ空けておく。**
    /// 押した時にここが割り込むと題名の幅が縮んで折り返してしまうため（b32 で直した）。
    static let badge: CGFloat = 19
    static let rowGap: CGFloat = 3           // 行と行のあいだ
    static let padLeading: CGFloat = 10
    static let padTrailing: CGFloat = 8
    static let padTop: CGFloat = 6
    static let padBottom: CGFloat = 4

    static func rowHeight(lines: Int) -> CGFloat {
        max(circleSlot, CGFloat(lines) * lineHeight) + rowGap
    }
}

struct HomeWidgetView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private var tint: Color { FaceStyle.color(entry.layout.reminderColor) }

    var body: some View {
        Group {
            if entry.items.isEmpty {
                Text(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ? "タスクなし" : "盤面タスクを一度開いて許可してください")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let plan = plan(for: geo.size)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.items) { item in
                            row(item, lineLimit: plan.lineLimit)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        // 既定の余白（16pt）は contentMarginsDisabled で外してある。ここが実際の余白
        .padding(.leading, Metric.padLeading)
        .padding(.trailing, Metric.padTrailing)
        .padding(.top, Metric.padTop)
        .padding(.bottom, Metric.padBottom)
        .containerBackground(.black, for: .widget)
    }

    // MARK: - 収まる件数を決める

    /// 件数を優先する。1行ずつなら入る件数をまず出し、
    /// **その件数のまま2行に伸ばしても収まる時だけ** 2行を許す。
    /// 収まらないなら題名を1行に切って（右端を落として）件数を保つ。
    private func plan(for size: CGSize) -> (items: [HomeItem], lineLimit: Int) {
        let textWidth = size.width - Metric.circleSlot - Metric.gap - Metric.badge
        let oneLine = Metric.rowHeight(lines: 1)
        let maxCount = max(1, Int(size.height / oneLine))
        let items = Array(entry.items.prefix(maxCount))

        let needed = items.reduce(CGFloat.zero) { total, item in
            let lines = estimatedWidth(item.title) <= textWidth * 0.95 ? 1 : 2
            return total + Metric.rowHeight(lines: lines)
        }
        return (items, needed <= size.height ? 2 : 1)
    }

    /// 題名の幅の見当。全角はフォントの大きさ、半角はその半分強で数える。
    private func estimatedWidth(_ title: String) -> CGFloat {
        title.unicodeScalars.reduce(CGFloat.zero) { width, scalar in
            width + (scalar.value < 0x2E80 ? Metric.font * 0.55 : Metric.font)
        }
    }

    // MARK: - 1行

    private func row(_ item: HomeItem, lineLimit: Int) -> some View {
        let waiting = (item.deadline ?? .distantPast) > entry.date
        return HStack(alignment: .top, spacing: Metric.gap) {
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
                .frame(width: 18, height: 18)
                .frame(width: Metric.circleSlot, height: Metric.circleSlot)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: Metric.font, weight: .medium))
                .foregroundStyle(waiting ? Color(white: 0.5) : .white)
                .strikethrough(waiting, color: Color(white: 0.5))
                .lineLimit(lineLimit)
                .truncationMode(.tail)          // 入らない分は右端を落とす。折り返さない
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            // 押していない時も同じ幅を占める。押した瞬間に題名の幅が変わらないように
            ZStack {
                if waiting, let deadline = item.deadline {
                    ProgressView(timerInterval: deadline.addingTimeInterval(-PendingStore.grace)...deadline,
                                 countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.circular)
                        .tint(tint)
                    Text("\(max(1, Int(deadline.timeIntervalSince(entry.date).rounded(.up))))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .frame(width: Metric.badge, height: Metric.badge)
        }
        .frame(minHeight: Metric.circleSlot, alignment: .top)
        .padding(.bottom, Metric.rowGap)
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
        .description("リマインダーをホーム画面から完了できます。○を押して5秒以内なら取り消せます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // 既定の余白（16pt）を外して自分で詰める。上と左をもう少し使うため
        .contentMarginsDisabled()
    }
}

@main
struct BanmenTaskHomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BanmenTaskHomeWidget()
    }
}

import Foundation
import EventKit
import WidgetKit

/// EventKit から「対象リスト」の未完了リマインダーと、今日の予定を読み、
/// 文字盤に送る FacePayload を組み立てる。並び順は priority(1〜9) に焼き込む。
///
/// 並び順のルール:
///   priority 1〜9 の項目を昇順で先頭に、0（未設定）の項目は作成日順で後ろに置く。
///   純正アプリで新規追加した項目は priority 0 なので自動的に末尾に来る。
///   自作アプリでドラッグ並べ替えすると、その順序が 1〜9 として保存される。
@MainActor
final class ReminderSource: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String          // EKCalendarItem.calendarItemIdentifier
        var title: String
        var priority: Int       // 0 = 未設定, 1 = 最優先 … 9 = 最低
        let created: Date
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var events: [FaceItem] = []
    @Published private(set) var listNames: [String] = []
    @Published private(set) var accessGranted = false
    @Published private(set) var calendarGranted = false
    @Published private(set) var errorMessage: String?
    @Published var listName: String {
        didSet {
            LayoutStore.listName = listName
            Task { await reload() }
        }
    }
    @Published var layout: FaceLayout {
        didSet {
            LayoutStore.save(layout)
            Task { await reload() }
        }
    }

    /// 送るリマインダーの件数。最大4行＋埋め草の分
    static let reminderCount = 6

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var isCommitting = false

    init() {
        // 旧バージョンは UserDefaults.standard に保存していたので、1回だけ引き継ぐ
        if let old = UserDefaults.standard.string(forKey: "listName") {
            LayoutStore.listName = old
            UserDefaults.standard.removeObject(forKey: "listName")
        }
        listName = LayoutStore.listName
        layout = LayoutStore.load()
        #if DEBUG
        // スクリーンショット用。BT_LAYOUT="2,2" のように「リマインダー数,予定数」を渡す
        if let spec = ProcessInfo.processInfo.environment["BT_LAYOUT"] {
            let n = spec.split(separator: ",").compactMap { Int($0) }
            if n.count == 2 { layout = FaceLayout(reminders: n[0], calendar: n[1]) }
        }
        #endif
        // 純正アプリ側の変更（完了・追加・編集・予定の変更）を拾って再読込する
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isCommitting else { return }
                await self.reload()
            }
        }
    }

    // MARK: - 読み込み

    func requestAccess() async {
        do {
            accessGranted = try await store.requestFullAccessToReminders()
        } catch {
            errorMessage = "リマインダーへのアクセス失敗: \(error.localizedDescription)"
            return
        }
        guard accessGranted else {
            errorMessage = "設定 → プライバシー → リマインダー で許可してください"
            return
        }
        if layout.usesCalendar { await requestCalendarAccess() }
        await reload()
        #if DEBUG
        // スクリーンショット用の見本。シミュレータで BT_DEMO=1 を付けて起動した時だけ、空のリストに書き込む
        if ProcessInfo.processInfo.environment["BT_DEMO"] != nil, items.isEmpty { await seedDemo() }
        #endif
    }

    #if DEBUG
    private func seedDemo() async {
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName })
                ?? store.calendars(for: .reminder).first else { return }
        listName = calendar.title
        let titles = ["iPhone返送", "バットテープ巻く", "牛乳を買う", "図書館に本を返す", "振込", "写真を整理"]
        for (i, title) in titles.enumerated() {
            let r = EKReminder(eventStore: store)
            r.title = title
            r.calendar = calendar
            r.priority = i < 4 ? i + 1 : 0
            try? store.save(r, commit: false)
        }
        try? store.commit()
        await seedDemoEvents()
        await reload()
    }

    /// スクリーンショット用の予定。これから24時間で、終日でないもの
    private func seedDemoEvents() async {
        guard EventSource.isAuthorized, EventSource.upcoming24h(store).isEmpty,
              let calendar = store.defaultCalendarForNewEvents else { return }
        for (hours, title) in [(2.0, "打ち合わせ"), (5.0, "歯医者")] {
            let e = EKEvent(eventStore: store)
            e.title = title
            e.calendar = calendar
            e.startDate = Date.now.addingTimeInterval(hours * 3600)
            e.endDate = e.startDate.addingTimeInterval(3600)
            try? store.save(e, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
    #endif

    /// カレンダーは使うモードに切り替えた時に初めて聞く
    func requestCalendarAccess() async {
        calendarGranted = await EventSource.requestAccess(store)
        if !calendarGranted {
            errorMessage = "設定 → プライバシー → カレンダー で許可すると予定を出せます"
        }
    }

    func reload() async {
        guard accessGranted else { return }
        let calendars = store.calendars(for: .reminder)
        listNames = calendars.map(\.title).sorted()

        guard let calendar = calendars.first(where: { $0.title == listName }) else {
            items = []
            errorMessage = "リスト「\(listName)」が見つかりません"
            return
        }
        errorMessage = nil

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        items = reminders
            .map { Item(id: $0.calendarItemIdentifier,
                        title: $0.title ?? "",
                        priority: $0.priority,
                        created: $0.creationDate ?? .distantPast) }
            .sorted(by: Self.order)

        calendarGranted = EventSource.isAuthorized
        events = layout.usesCalendar ? EventSource.upcoming24h(store) : []
        // ホーム画面ウィジェットにも反映
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func order(_ a: Item, _ b: Item) -> Bool {
        let pa = a.priority == 0 ? Int.max : a.priority
        let pb = b.priority == 0 ? Int.max : b.priority
        if pa != pb { return pa < pb }
        return a.created < b.created
    }

    // MARK: - 並べ替え → priority に保存

    func move(from source: IndexSet, to destination: Int) async {
        items.move(fromOffsets: source, toOffset: destination)
        await commitOrder()
    }

    private func commitOrder() async {
        isCommitting = true
        defer { isCommitting = false }

        let snapshot = items
        var changed = false
        for (index, item) in snapshot.enumerated() {
            let want = index < 9 ? index + 1 : 0
            guard item.priority != want,
                  let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder
            else { continue }
            reminder.priority = want
            do {
                try store.save(reminder, commit: false)
                changed = true
            } catch {
                errorMessage = "保存失敗: \(error.localizedDescription)"
            }
        }
        if changed {
            do { try store.commit() } catch { errorMessage = "commit 失敗: \(error.localizedDescription)" }
        }
        await reload()
    }

    // MARK: - 編集（追加・完了・改名）。書き込み先は純正リマインダー

    func add(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName })
        else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        reminder.priority = 0   // 未設定 → 末尾に並ぶ。上に持っていくのはドラッグで
        await write { try store.save(reminder, commit: true) }
    }

    func complete(id: String) async {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        await write { try store.save(reminder, commit: true) }
    }

    func rename(id: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return }
        reminder.title = trimmed
        await write { try store.save(reminder, commit: true) }
    }

    private func write(_ body: () throws -> Void) async {
        isCommitting = true
        defer { isCommitting = false }
        do { try body() } catch { errorMessage = "保存失敗: \(error.localizedDescription)" }
        await reload()
    }

    /// Watch からの完了要求。画面が無い状態で呼ばれるので自前のストアで処理する。
    static func completeHeadless(id: String) -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return false }
        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        reminder.isCompleted = true
        do { try store.save(reminder, commit: true); return true } catch { return false }
    }

    // MARK: - Watch へ送る内容

    var facePayload: FacePayload { Self.facePayload(layout: layout, items: items, events: events) }

    private static func facePayload(layout: FaceLayout, items: [Item], events: [FaceItem]) -> FacePayload {
        let top = items.prefix(reminderCount).map {
            FaceItem(id: $0.id, kind: .reminder, title: $0.title, start: nil)
        }
        return FacePayload(layout: layout, reminders: top, events: events, updatedAt: .now)
    }

    /// 画面に依存せず、保存済みの設定から組み立てる（BGTask / App Intent / Watch からの要求）。
    /// リマインダー未許可なら nil。
    static func fetchFacePayload() async -> FacePayload? {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }
        let store = EKEventStore()
        let listName = LayoutStore.listName
        let layout = LayoutStore.load()
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName })
        else { return nil }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        let items = reminders
            .map { Item(id: $0.calendarItemIdentifier,
                        title: $0.title ?? "",
                        priority: $0.priority,
                        created: $0.creationDate ?? .distantPast) }
            .sorted(by: order)
        let events = layout.usesCalendar ? EventSource.upcoming24h(store) : []
        return facePayload(layout: layout, items: items, events: events)
    }
}

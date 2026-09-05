import Foundation
import EventKit

/// EventKit から「対象リスト」の未完了リマインダーを読み、
/// 並び順を priority(1〜9) に焼き込む。
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
    @Published private(set) var listNames: [String] = []
    @Published private(set) var accessGranted = false
    @Published private(set) var errorMessage: String?
    @Published var listName: String {
        didSet {
            UserDefaults.standard.set(listName, forKey: Self.listNameKey)
            Task { await reload() }
        }
    }

    private static let listNameKey = "listName"
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var isCommitting = false

    init() {
        listName = UserDefaults.standard.string(forKey: Self.listNameKey) ?? "基本"
        // 純正アプリ側の変更（完了・追加・編集）を拾って再読込する
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
        await reload()
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
    }

    static func order(_ a: Item, _ b: Item) -> Bool {
        let pa = a.priority == 0 ? Int.max : a.priority
        let pb = b.priority == 0 ? Int.max : b.priority
        if pa != pb { return pa < pb }
        return a.created < b.created
    }

    // MARK: - 並べ替え → priority に保存

    /// UI 上で並べ替えた結果を受け取り、先頭から priority 1,2,3… を書き込む。
    /// 10件目以降は 0（未設定）に戻す。
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

    // MARK: - Watch へ送る内容

    var faceTasks: FaceTasks {
        FaceTasks(lines: Array(items.prefix(2).map(\.title)), updatedAt: .now)
    }
}

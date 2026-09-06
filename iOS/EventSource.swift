import Foundation
import EventKit

/// 今日の予定のうち「終日でない・まだ始まっていない」ものを EventKit から読む。
/// Google カレンダーは iOS の設定でアカウントを追加しておけば同じ経路で読める。
enum EventSource {
    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    @discardableResult
    static func requestAccess(_ store: EKEventStore) async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// 今日これからの予定（終日を除く）。開始時刻順。
    static func todayUpcoming(_ store: EKEventStore, now: Date = .now) -> [FaceItem] {
        guard isAuthorized else { return [] }
        let cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { FaceItem(id: $0.eventIdentifier ?? UUID().uuidString,
                            kind: .event,
                            title: $0.title ?? "",
                            start: $0.startDate) }
    }
}

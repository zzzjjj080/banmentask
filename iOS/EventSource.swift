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

    /// これから24時間の予定。
    /// - 時刻のある予定：開始から1時間たつまで（始まっても1時間は残す）
    /// - 終日の予定：終わっていないもの。時刻の予定で行が埋まれば出ない（FaceComposer が後ろに並べる）
    static func upcoming24h(_ store: EKEventStore, now: Date = .now) -> [FaceItem] {
        guard isAuthorized else { return [] }
        let from = now.addingTimeInterval(-FaceItem.keepAfterStart)
        let predicate = store.predicateForEvents(withStart: from, end: now.addingTimeInterval(24 * 60 * 60), calendars: nil)
        let events = store.events(matching: predicate)
        let timed = events
            .filter { !$0.isAllDay && $0.startDate > from }
            .sorted { $0.startDate < $1.startDate }
            .map { FaceItem(id: $0.eventIdentifier ?? UUID().uuidString, kind: .event,
                            title: $0.title ?? "", start: $0.startDate) }
        let today = Calendar.current.startOfDay(for: now)
        let allDay = events
            .filter { $0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            // 何日も続く終日予定は、今日にかかっていれば「今日の終日」として出す
            .map { FaceItem(id: $0.eventIdentifier ?? UUID().uuidString, kind: .event,
                            title: $0.title ?? "", start: max($0.startDate, today),
                            allDay: true, end: $0.endDate) }
        return timed + allDay
    }
}

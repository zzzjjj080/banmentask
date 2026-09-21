import Foundation
import EventKit

/// これから24時間の予定を EventKit から読む。
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
    /// - 祝日のカレンダーは読まない。同じ名前・同じ開始の予定は1つにまとめる
    ///   （iCloud と Google の両方に「日本の祝日」があると、敬老の日が2つ出ていた）
    static func upcoming24h(_ store: EKEventStore, now: Date = .now, includeAllDay: Bool = true) -> [FaceItem] {
        guard isAuthorized else { return [] }
        let calendars = store.calendars(for: .event).filter { !isHolidayCalendar($0) }
        // 空の配列を渡すと「全部」と同じになりうるので、読むカレンダーが無ければ何も出さない
        guard !calendars.isEmpty else { return [] }
        let from = now.addingTimeInterval(-FaceItem.keepAfterStart)
        let predicate = store.predicateForEvents(withStart: from, end: now.addingTimeInterval(24 * 60 * 60), calendars: calendars)
        var seen = Set<String>()
        let events = store.events(matching: predicate).filter {
            seen.insert("\($0.title ?? "")|\($0.isAllDay)|\($0.startDate.timeIntervalSince1970)").inserted
        }
        let timed = events
            .filter { !$0.isAllDay && $0.startDate > from }
            .sorted { $0.startDate < $1.startDate }
            .map { FaceItem(id: $0.eventIdentifier ?? UUID().uuidString, kind: .event,
                            title: $0.title ?? "", start: $0.startDate) }
        let today = Calendar.current.startOfDay(for: now)
        let allDay = !includeAllDay ? [] : events
            .filter { $0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            // 何日も続く終日予定は、今日にかかっていれば「今日の終日」として出す
            .map { FaceItem(id: $0.eventIdentifier ?? UUID().uuidString, kind: .event,
                            title: $0.title ?? "", start: max($0.startDate, today),
                            allDay: true, end: $0.endDate) }
        return timed + allDay
    }

    /// 祝日のカレンダーか。iOS に「祝日かどうか」を返す API は無いので名前で見分ける。
    /// iCloud の「日本の祝日」（照会カレンダー）も、Google の「日本の祝日」もこれで外れる
    static func isHolidayCalendar(_ calendar: EKCalendar) -> Bool {
        let title = calendar.title.lowercased()
        return ["祝日", "休日", "祭日", "holiday"].contains { title.contains($0) }
    }
}

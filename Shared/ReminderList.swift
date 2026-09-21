import EventKit

/// 文字盤に出すリマインダーのリストを決める。
/// 選んだ名前のリストが無ければ、端末の既定のリストを使う。
/// 既定の名前「基本」は日本語の端末の話で、英語の端末では「Reminders」になる。
/// 名前だけで探していたころは、海外の端末でアプリもウィジェットも文字盤も空になった。
enum ReminderList {
    static func find(in store: EKEventStore, named name: String) -> EKCalendar? {
        let lists = store.calendars(for: .reminder)
        return lists.first(where: { $0.title == name })
            ?? store.defaultCalendarForNewReminders()
            ?? lists.first
    }
}

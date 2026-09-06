import Foundation

/// どのビルドが実機に入っているかを見分けるための印。コードを push するたびに増やす。
/// iPhone / Watch の画面右上に極小で出る。文字盤には出さない。
enum BuildInfo {
    static let marker = "b26"
}

enum AppGroup {
    /// Certificates, Identifiers & Profiles で先に登録しておくこと。
    static let identifier = "group.com.zzzjjj080.banmentask"
}

// MARK: - 文字盤に出す候補

/// 文字盤に何行出し、そのうち何行を予定に使うか
struct FaceLayout: Codable, Equatable {
    /// 文字盤に出せる最大行数
    static let maxLines = 4
    var lines: Int          // 1〜maxLines
    var calendarSlots: Int  // 0〜lines
    var reminderColor: Int  // FaceStyle.palette の添字
    var eventColor: Int

    static let `default` = FaceLayout(lines: 2, calendarSlots: 0)

    init(lines: Int, calendarSlots: Int, reminderColor: Int = 2, eventColor: Int = 9) {
        self.lines = lines
        self.calendarSlots = calendarSlots
        self.reminderColor = reminderColor
        self.eventColor = eventColor
    }
    init(reminders: Int, calendar: Int, reminderColor: Int = 2, eventColor: Int = 9) {
        self.init(lines: reminders + calendar, calendarSlots: calendar,
                  reminderColor: reminderColor, eventColor: eventColor)
    }

    /// 古い保存データ（色なし）も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = try c.decode(Int.self, forKey: .lines)
        calendarSlots = try c.decode(Int.self, forKey: .calendarSlots)
        reminderColor = try c.decodeIfPresent(Int.self, forKey: .reminderColor) ?? 2
        eventColor = try c.decodeIfPresent(Int.self, forKey: .eventColor) ?? 9
    }

    func color(_ kind: FaceItem.Kind) -> Int { kind == .reminder ? reminderColor : eventColor }

    var reminderSlots: Int { lines - calendarSlots }
    var usesCalendar: Bool { calendarSlots > 0 }
    var usesReminders: Bool { reminderSlots > 0 }

    /// 範囲に収める（合計1〜maxLines）
    var clamped: FaceLayout {
        let l = min(max(lines, 1), Self.maxLines)
        return FaceLayout(lines: l, calendarSlots: min(max(calendarSlots, 0), l))
    }
}

/// 文字盤の1行（文言と種類）。色分けに使う。
struct FaceLine: Equatable {
    let text: String
    let kind: FaceItem.Kind
}

/// 文字盤に出す1件。リマインダーか、今日のこれからの予定か。
struct FaceItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case reminder, event }
    let id: String          // calendarItemIdentifier / eventIdentifier
    let kind: Kind
    let title: String
    let start: Date?        // 予定のみ

    /// 文字盤に出す文言。予定は「14:00 歯医者」。
    var displayText: String {
        guard kind == .event, let start else { return title }
        let time = Self.hhmm.string(from: start)
        let prefix = Calendar.current.isDateInToday(start) ? "" : "明日"
        return "\(prefix)\(time) \(title)"
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// iPhone → Watch へ送る一式。文字盤の2行はここから FaceComposer が組み立てる。
struct FacePayload: Codable, Equatable {
    var layout: FaceLayout
    var reminders: [FaceItem]   // 上位数件（並び順どおり）
    var events: [FaceItem]      // これから24時間の予定のうち終日でないもの（開始時刻順）。開始済みは受信側で落とす
    var updatedAt: Date

    static let empty = FacePayload(layout: .default, reminders: [], events: [], updatedAt: .distantPast)
    static let placeholder = FacePayload(
        layout: FaceLayout(lines: 2, calendarSlots: 1),
        reminders: [FaceItem(id: "r1", kind: .reminder, title: "洗濯する", start: nil)],
        events: [FaceItem(id: "e1", kind: .event, title: "歯医者",
                          start: Calendar.current.date(byAdding: .hour, value: 2, to: .now))],
        updatedAt: .now)

    /// 「前回と同じ内容か」を見るための署名。updatedAt は含めない。
    var signature: String {
        let r = reminders.map { "\($0.id):\($0.title)" }.joined(separator: "|")
        let e = events.map { "\($0.id):\($0.title):\($0.start?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
        return "\(layout.lines)/\(layout.calendarSlots)#\(r)#\(e)"
    }
}

/// 文字盤の2行を決める。iPhone のプレビュー・Watch アプリ・ウィジェットの3か所で同じ結果になる。
enum FaceComposer {
    /// 行数と割り当てに従って埋める。
    /// リマインダー枠 → 予定枠 の順に並べ、片方が足りなければもう片方で埋める。
    static func items(_ p: FacePayload, at now: Date) -> [FaceItem] {
        let layout = p.layout.clamped
        let upcoming = p.events.filter { ($0.start ?? .distantPast) > now }
        var reminders = Array(p.reminders.prefix(layout.reminderSlots))
        var events = Array(upcoming.prefix(layout.calendarSlots))
        // 埋め草
        if reminders.count < layout.reminderSlots {
            let more = layout.reminderSlots - reminders.count
            events += upcoming.dropFirst(events.count).prefix(more)
        }
        if events.count < layout.calendarSlots {
            let more = layout.calendarSlots - events.count
            reminders += p.reminders.dropFirst(reminders.count).prefix(more)
        }
        return Array((reminders + events).prefix(layout.lines))
    }

    static func lines(_ p: FacePayload, at now: Date) -> [String] {
        items(p, at: now).map(\.displayText)
    }

    static func faceLines(_ p: FacePayload, at now: Date) -> [FaceLine] {
        items(p, at: now).map { FaceLine(text: $0.displayText, kind: $0.kind) }
    }

    /// iPhone のプレビュー用。実データではなく「リマインダー1 / 予定1」のような例文。
    static func exampleLines(_ layout: FaceLayout) -> [FaceLine] {
        let l = layout.clamped
        return (0..<l.reminderSlots).map { FaceLine(text: "リマインダー\($0 + 1)", kind: .reminder) }
             + (0..<l.calendarSlots).map { FaceLine(text: "予定\($0 + 1)", kind: .event) }
    }

    /// 表示が変わる時刻。予定の開始時刻ごとに文字盤を切り替えるためにウィジェットが使う。
    static func changePoints(_ p: FacePayload, after now: Date) -> [Date] {
        guard p.layout.usesCalendar else { return [] }
        return p.events.compactMap(\.start).filter { $0 > now }.sorted()
    }
}

// MARK: - 表示設定の保存（iPhone アプリ ⇄ iPhone のホームウィジェット）

enum LayoutStore {
    private static let key = "faceLayout"
    private static let listKey = "listName"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    static func load() -> FaceLayout {
        guard let data = defaults?.data(forKey: key),
              let l = try? JSONDecoder().decode(FaceLayout.self, from: data) else { return .default }
        return l.clamped
    }
    static func save(_ l: FaceLayout) {
        defaults?.set(try? JSONEncoder().encode(l.clamped), forKey: key)
    }
    static var listName: String {
        get { defaults?.string(forKey: listKey) ?? "基本" }
        set { defaults?.set(newValue, forKey: listKey) }
    }
}

// MARK: - 完了の猶予（iPhone のホームウィジェット用）

/// ○を押してから完了するまでの3秒を、ウィジェット拡張の複数の呼び出しで共有する。
enum PendingStore {
    static let grace: TimeInterval = 3
    private static let key = "pendingCompletions"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    /// id → 押した時刻
    static func load() -> [String: Date] {
        guard let data = defaults?.data(forKey: key),
              let d = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        // 古いものは捨てる
        return d.filter { Date.now.timeIntervalSince($0.value) < grace + 30 }
    }
    static func save(_ d: [String: Date]) {
        defaults?.set(try? JSONEncoder().encode(d), forKey: key)
    }
    static func deadline(for id: String) -> Date? {
        load()[id].map { $0.addingTimeInterval(grace) }
    }
}

// MARK: - App Group 経由の永続化（Watch アプリ ⇄ ウィジェット拡張）

enum TaskStore {
    private static let key = "facePayload"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    static func load() -> FacePayload {
        guard let data = defaults?.data(forKey: key),
              let p = try? JSONDecoder().decode(FacePayload.self, from: data)
        else { return .empty }
        return p
    }

    static func save(_ p: FacePayload) {
        guard let data = try? JSONEncoder().encode(p) else { return }
        defaults?.set(data, forKey: key)
    }
}

// MARK: - WatchConnectivity の辞書との相互変換（iPhone ⇄ Watch）

extension FacePayload {
    private static let key = "json"

    var payload: [String: Any] {
        ["json": (try? JSONEncoder().encode(self)) ?? Data()]
    }

    init?(payload: [String: Any]) {
        guard let data = payload[Self.key] as? Data,
              let p = try? JSONDecoder().decode(FacePayload.self, from: data)
        else { return nil }
        self = p
    }
}

import Foundation

/// どのビルドが実機に入っているかを見分けるための印。コードを push するたびに増やす。
/// iPhone / Watch の画面右上に極小で出る。文字盤には出さない。
enum BuildInfo {
    static let marker = "b16"
}

enum AppGroup {
    /// Certificates, Identifiers & Profiles で先に登録しておくこと。
    static let identifier = "group.com.zzzjjj080.banmentask"
}

// MARK: - 文字盤に出す候補

/// 文字盤の2行をどう埋めるか
enum FaceMode: String, Codable, CaseIterable, Identifiable {
    case reminders   // リマインダーのみ
    case mixed       // 1つずつ（リマインダー1件＋次の予定1件）
    case calendar    // カレンダーのみ

    var id: String { rawValue }
    var label: String {
        switch self {
        case .reminders: return "リマインダー"
        case .mixed: return "1つずつ"
        case .calendar: return "カレンダー"
        }
    }
    var usesCalendar: Bool { self != .reminders }
    var usesReminders: Bool { self != .calendar }
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
        return "\(Self.hhmm.string(from: start)) \(title)"
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
    var mode: FaceMode
    var reminders: [FaceItem]   // 上位数件（並び順どおり）
    var events: [FaceItem]      // 今日の予定のうち終日でないもの（開始時刻順）。開始済みは受信側で落とす
    var updatedAt: Date

    static let empty = FacePayload(mode: .reminders, reminders: [], events: [], updatedAt: .distantPast)
    static let placeholder = FacePayload(
        mode: .mixed,
        reminders: [FaceItem(id: "r1", kind: .reminder, title: "洗濯する", start: nil)],
        events: [FaceItem(id: "e1", kind: .event, title: "歯医者",
                          start: Calendar.current.date(byAdding: .hour, value: 2, to: .now))],
        updatedAt: .now)

    /// 「前回と同じ内容か」を見るための署名。updatedAt は含めない。
    var signature: String {
        let r = reminders.map { "\($0.id):\($0.title)" }.joined(separator: "|")
        let e = events.map { "\($0.id):\($0.title):\($0.start?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
        return "\(mode.rawValue)#\(r)#\(e)"
    }
}

/// 文字盤の2行を決める。iPhone のプレビュー・Watch アプリ・ウィジェットの3か所で同じ結果になる。
enum FaceComposer {
    static let slots = 2

    static func items(_ p: FacePayload, at now: Date) -> [FaceItem] {
        let upcoming = p.events.filter { ($0.start ?? .distantPast) > now }
        var out: [FaceItem] = []
        switch p.mode {
        case .reminders:
            out = Array(p.reminders.prefix(slots))
        case .calendar:
            out = Array(upcoming.prefix(slots))
        case .mixed:
            if let r = p.reminders.first { out.append(r) }
            if let e = upcoming.first { out.append(e) }
            // 片方が足りなければもう片方で埋める
            var moreR = p.reminders.dropFirst().makeIterator()
            var moreE = upcoming.dropFirst().makeIterator()
            while out.count < slots {
                if let r = moreR.next() { out.append(r) }
                else if let e = moreE.next() { out.append(e) }
                else { break }
            }
        }
        return out
    }

    static func lines(_ p: FacePayload, at now: Date) -> [String] {
        items(p, at: now).map(\.displayText)
    }

    /// 表示が変わる時刻。予定の開始時刻ごとに文字盤を切り替えるためにウィジェットが使う。
    static func changePoints(_ p: FacePayload, after now: Date) -> [Date] {
        guard p.mode.usesCalendar else { return [] }
        return p.events.compactMap(\.start).filter { $0 > now }.sorted()
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

import Foundation

/// iOS / Watch / Widget の3ターゲットで共有する定数とモデル。
/// どのビルドが実機に入っているかを見分けるための印。コードを push するたびに増やす。
/// Watch アプリの画面と iPhone の状態欄に出る。文字盤には出さない。
enum BuildInfo {
    static let marker = "b7"
}

enum AppGroup {
    /// Certificates, Identifiers & Profiles で先に登録しておくこと。
    static let identifier = "group.com.zzzjjj080.banmentask"
}

/// 文字盤に出す内容。上位2件だけを持つ。
struct FaceTasks: Codable, Equatable {
    var lines: [String]
    /// lines と同じ並びの calendarItemIdentifier。Watch から完了する時に使う。
    var ids: [String]
    var updatedAt: Date

    init(lines: [String], ids: [String] = [], updatedAt: Date) {
        self.lines = lines
        self.ids = ids
        self.updatedAt = updatedAt
    }

    /// 古い保存データ（ids なし）も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = try c.decode([String].self, forKey: .lines)
        ids = try c.decodeIfPresent([String].self, forKey: .ids) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    static let empty = FaceTasks(lines: [], updatedAt: .distantPast)
    static let placeholder = FaceTasks(lines: ["iPhone返送", "バットテープ巻く"], updatedAt: .now)

    var first: String { lines.first ?? "" }
    var second: String { lines.count > 1 ? lines[1] : "" }
}

// MARK: - App Group 経由の永続化（Watch アプリ ⇄ ウィジェット拡張）

enum TaskStore {
    private static let key = "faceTasks"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    static func load() -> FaceTasks {
        guard let data = defaults?.data(forKey: key),
              let tasks = try? JSONDecoder().decode(FaceTasks.self, from: data)
        else { return .empty }
        return tasks
    }

    static func save(_ tasks: FaceTasks) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults?.set(data, forKey: key)
    }
}

// MARK: - WatchConnectivity の辞書との相互変換（iPhone ⇄ Watch）

extension FaceTasks {
    var payload: [String: Any] {
        ["lines": lines, "ids": ids, "updatedAt": updatedAt.timeIntervalSince1970]
    }

    init?(payload: [String: Any]) {
        guard let lines = payload["lines"] as? [String] else { return nil }
        let ids = payload["ids"] as? [String] ?? []
        let t = payload["updatedAt"] as? TimeInterval ?? Date.now.timeIntervalSince1970
        self.init(lines: lines, ids: ids, updatedAt: Date(timeIntervalSince1970: t))
    }
}

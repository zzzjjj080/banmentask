import Foundation

/// iOS / Watch / Widget の3ターゲットで共有する定数とモデル。
enum AppGroup {
    /// Certificates, Identifiers & Profiles で先に登録しておくこと。
    static let identifier = "group.com.zzzjjj080.banmentask"
}

/// 文字盤に出す内容。上位2件だけを持つ。
struct FaceTasks: Codable, Equatable {
    var lines: [String]
    var updatedAt: Date

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
        ["lines": lines, "updatedAt": updatedAt.timeIntervalSince1970]
    }

    init?(payload: [String: Any]) {
        guard let lines = payload["lines"] as? [String] else { return nil }
        let t = payload["updatedAt"] as? TimeInterval ?? Date.now.timeIntervalSince1970
        self.init(lines: lines, updatedAt: Date(timeIntervalSince1970: t))
    }
}

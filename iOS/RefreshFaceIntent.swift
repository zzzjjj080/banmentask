import AppIntents

/// ショートカット / Siri から呼べる「盤面タスクを更新」。
///
/// 想定する使い方:
///   ショートカット → オートメーション → 「App」→ リマインダー →「閉じられている」→
///   すぐに実行 → アクション「盤面タスクを更新」
/// これで純正リマインダーを閉じるたびに文字盤が更新される。
struct RefreshFaceIntent: AppIntent {
    static var title: LocalizedStringResource = "盤面タスクを更新"
    /// **説明文に "Apple" を入れてはいけない。** 入れると Apple 側の処理で
    /// 「Invalid Siri Support. App Intent description ... cannot contain "apple"」で
    /// ビルドが弾かれる。アップロードは成功と出るのに、ビルドが現れないので気づきにくい。
    static var description = IntentDescription("リマインダーを読み直して腕時計の文字盤を更新します")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await BackgroundRefresh.refreshAndSend(reason: "intent", force: true)
        return .result()
    }
}

struct BanmenTaskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshFaceIntent(),
            phrases: ["\(.applicationName)を更新"],
            shortTitle: "盤面タスクを更新",
            systemImageName: "applewatch"
        )
    }
}

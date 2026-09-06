import Foundation
import EventKit
import BackgroundTasks

/// iPhone アプリが前面にいない時にリマインダーを読み直して Watch へ送る経路。
///
/// 呼び出し元は3つ:
///   1. BGAppRefreshTask — iOS が機会を見て起こす（15分〜数時間おき。タイミングは iOS 任せ）
///   2. RefreshFaceIntent — ショートカットのオートメーションから
///   3. Watch からの sendMessage — Watch アプリを開いた時
enum BackgroundRefresh {
    static let taskIdentifier = "com.zzzjjj080.banmentask.refresh"

    /// アプリ起動時（App.init）に必ず呼ぶ。起動完了後の登録は拒否される。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    /// アプリが背面に回るたびに次回分を予約する。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            await refreshAndSend(reason: "bgtask", force: false)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// EventKit を読み、上位2件を Watch へ送る。
    /// force=false なら前回送信分と同じ内容はスキップして転送枠を守る。
    @discardableResult
    static func refreshAndSend(reason: String, force: Bool) async -> FacePayload? {
        guard let tasks = await ReminderSource.fetchFacePayload() else { return nil }
        await PhoneSession.shared.sendIfChanged(tasks, force: force, reason: reason)
        return tasks
    }
}

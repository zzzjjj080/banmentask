import Foundation
import WatchConnectivity
import WidgetKit

/// Watch 側の WatchConnectivity。
/// 受信 → App Group に保存 → ウィジェットのタイムラインを再読込、の3つだけを担当する。
@MainActor
final class WatchSession: NSObject, ObservableObject {
    @Published var tasks = TaskStore.load()

    override init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func apply(_ payload: [String: Any]) {
        guard let incoming = FaceTasks(payload: payload) else { return }
        TaskStore.save(incoming)
        tasks = incoming
        // ここが文字盤更新のトリガー。これを呼ばないと保存しても盤面は変わらない。
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // 起動時点で iPhone が置いていった applicationContext があれば取り込む
        let context = session.receivedApplicationContext
        Task { @MainActor in
            if !context.isEmpty { apply(context) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in apply(userInfo) }
    }
}

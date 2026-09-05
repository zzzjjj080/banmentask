import Foundation
import WatchConnectivity
import WidgetKit

/// Watch 側の WatchConnectivity。
/// 受信 → App Group に保存 → ウィジェットのタイムラインを再読込。
/// 加えて iPhone へ「読み直して」「これを完了して」を投げる。
@MainActor
final class WatchSession: NSObject, ObservableObject {
    static let shared = WatchSession()

    @Published var tasks = TaskStore.load()
    @Published var isBusy = false
    @Published var lastError: String?

    private override init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// iPhone に「いまリマインダーを読み直して」と頼む。
    /// iPhone アプリが起動していなくても裏で起こされて応答する。
    func requestRefresh() {
        ask(["request": "refresh"])
    }

    /// iPhone に「この項目を完了して」と頼む。返事で次の上位2件が届く。
    func complete(id: String) {
        ask(["request": "complete", "id": id])
    }

    private func ask(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            lastError = "iPhone に接続できません"
            return
        }
        isBusy = true
        lastError = nil
        session.sendMessage(message, replyHandler: { reply in
            Task { @MainActor in
                self.isBusy = false
                if !reply.isEmpty { self.apply(reply) }
            }
        }, errorHandler: { error in
            Task { @MainActor in
                self.isBusy = false
                self.lastError = error.localizedDescription
            }
        })
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

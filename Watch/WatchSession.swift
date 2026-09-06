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

    /// 接続待ちの間に溜めておく要求。繋がった瞬間に投げる
    private var queued: [String: Any]?

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
            // 開いた直後は接続が立ち上がる前なので、少し待ってから諦める
            queued = message
            isBusy = true
            lastError = nil
            Task {
                try? await Task.sleep(for: .seconds(3))
                guard queued != nil else { return }   // その間に繋がって送れた
                queued = nil
                isBusy = false
                lastError = "iPhone に接続できません。近くにあるか確認してください"
            }
            return
        }
        queued = nil
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
        guard let incoming = FacePayload(payload: payload) else { return }
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

    /// 接続が立ち上がったら、待たせていた要求を投げる
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            if let m = queued { ask(m) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in apply(userInfo) }
    }
}

import Foundation
import WatchConnectivity

/// iPhone 側の WatchConnectivity。Watch へ FaceTasks を送る。
/// バックグラウンド起動（BGTask / App Intent / Watch からのメッセージ）でも
/// 同じインスタンスを使うため singleton にしている。
@MainActor
final class PhoneSession: NSObject, ObservableObject {
    static let shared = PhoneSession()

    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isComplicationEnabled = false
    @Published var remainingTransfers = 0
    @Published var lastResult = "未送信"

    private static let lastSentKey = "lastSentLines"

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 上位2件が前回送信分と違う時だけ送る（1日50回の転送枠を守る）。
    func sendIfChanged(_ tasks: FaceTasks, force: Bool) {
        let last = UserDefaults.standard.stringArray(forKey: Self.lastSentKey) ?? []
        guard force || tasks.lines != last else { return }
        UserDefaults.standard.set(tasks.lines, forKey: Self.lastSentKey)
        send(tasks)
    }

    /// 2経路で送る。
    /// - applicationContext: 「最新状態」を1つだけ保持し、Watch アプリ起動時に必ず届く
    /// - transferCurrentComplicationUserInfo: Watch アプリを裏で起こしてまで届ける（1日50回まで）
    func send(_ tasks: FaceTasks) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastResult = "WCSession 未接続"
            return
        }
        do {
            try session.updateApplicationContext(tasks.payload)
        } catch {
            lastResult = "applicationContext 失敗: \(error.localizedDescription)"
        }

        if session.isComplicationEnabled {
            session.transferCurrentComplicationUserInfo(tasks.payload)
            lastResult = "送信済み（コンプリケーション経由・残り \(session.remainingComplicationUserInfoTransfers) 回/日）"
        } else {
            session.transferUserInfo(tasks.payload)
            lastResult = "送信済み（通常転送。文字盤に未配置のため即時性なし）"
        }
        refresh()
    }

    func refresh() {
        let s = WCSession.default
        isPaired = s.isPaired
        isWatchAppInstalled = s.isWatchAppInstalled
        isComplicationEnabled = s.isComplicationEnabled
        remainingTransfers = s.remainingComplicationUserInfoTransfers
    }
}

extension PhoneSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in refresh() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in refresh() }
    }

    /// Watch アプリからの「いま読み直して」要求。
    /// iPhone アプリが起動していなくても、この呼び出しのために裏で起動される。
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "refresh" else {
            replyHandler([:])
            return
        }
        Task {
            let tasks = await BackgroundRefresh.refreshAndSend(reason: "watch", force: false)
            replyHandler(tasks?.payload ?? [:])
        }
    }
}

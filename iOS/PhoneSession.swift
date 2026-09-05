import Foundation
import WatchConnectivity

/// iPhone 側の WatchConnectivity。Watch へ FaceTasks を送る。
@MainActor
final class PhoneSession: NSObject, ObservableObject {
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isComplicationEnabled = false
    @Published var remainingTransfers = 0
    @Published var lastResult = "未送信"

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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
}

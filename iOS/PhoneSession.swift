import Foundation
import WatchConnectivity

/// iPhone 側の WatchConnectivity。Watch へ FacePayload を送る。
/// バックグラウンド起動（BGTask / App Intent / Watch からのメッセージ）でも
/// 同じインスタンスを使うため singleton にしている。
@MainActor
final class PhoneSession: NSObject, ObservableObject {
    static let shared = PhoneSession()

    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isComplicationEnabled = false
    @Published var remainingTransfers = 0
    @Published var lastResult: String {
        didSet { UserDefaults.standard.set(lastResult, forKey: Self.lastResultKey) }
    }

    private static let lastSentKey = "lastSentSignature"
    private static let lastResultKey = "lastResult"

    private override init() {
        lastResult = UserDefaults.standard.string(forKey: Self.lastResultKey) ?? "未送信"
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 裏起動（オートメーション / BGTask）直後は activate() が終わっていないので、
    /// 最大5秒待つ。ここを待たずに送ると「未接続」で捨てられる。
    private func ensureActivated() async -> Bool {
        let session = WCSession.default
        if session.activationState != .activated { session.activate() }
        for _ in 0..<50 where session.activationState != .activated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return session.activationState == .activated
    }

    /// 上位2件が前回送信分と違う時だけ送る（1日50回の転送枠を守る）。
    func sendIfChanged(_ payload: FacePayload, force: Bool, reason: String) async {
        let last = UserDefaults.standard.string(forKey: Self.lastSentKey) ?? ""
        guard force || payload.signature != last else { return }
        if await send(payload, reason: reason) {
            UserDefaults.standard.set(payload.signature, forKey: Self.lastSentKey)
        }
    }

    /// 2経路で送る。
    /// - applicationContext: 「最新状態」を1つだけ保持し、Watch アプリ起動時に必ず届く
    /// - transferCurrentComplicationUserInfo: Watch アプリを裏で起こしてまで届ける（1日50回まで）
    @discardableResult
    func send(_ tasks: FacePayload, reason: String) async -> Bool {
        let stamp = Date.now.formatted(date: .omitted, time: .shortened)
        guard await ensureActivated() else {
            lastResult = "\(stamp) \(reason): WCSession 未接続（5秒待っても接続できず）"
            return false
        }
        let session = WCSession.default
        do {
            try session.updateApplicationContext(tasks.payload)
        } catch {
            lastResult = "\(stamp) \(reason): applicationContext 失敗 \(error.localizedDescription)"
        }

        if session.isComplicationEnabled {
            session.transferCurrentComplicationUserInfo(tasks.payload)
            lastResult = "\(stamp) \(reason): 送信済み（文字盤経由・残り \(session.remainingComplicationUserInfoTransfers) 回/日）"
        } else {
            session.transferUserInfo(tasks.payload)
            lastResult = "\(stamp) \(reason): 送信済み（通常転送・文字盤に未配置）"
        }
        refresh()
        return true
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
        Task {
            switch message["request"] as? String {
            case "refresh":
                let tasks = await BackgroundRefresh.refreshAndSend(reason: "watch", force: false)
                replyHandler(tasks?.payload ?? [:])
            case "complete":
                if let id = message["id"] as? String {
                    _ = await ReminderSource.completeHeadless(id: id)
                }
                let tasks = await BackgroundRefresh.refreshAndSend(reason: "watch完了", force: true)
                replyHandler(tasks?.payload ?? [:])
            default:
                replyHandler([:])
            }
        }
    }
}

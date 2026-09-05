import WatchKit

/// iPhone からの transferCurrentComplicationUserInfo で裏起動された時、
/// 画面（SwiftUI の Scene）が作られる前に WCSession を立てておくための入口。
/// ここで立てないと、裏起動では delegate が無くて受信を取りこぼす。
@MainActor
final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        _ = WatchSession.shared
    }
}

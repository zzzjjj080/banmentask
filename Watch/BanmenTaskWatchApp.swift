import SwiftUI

@main
struct BanmenTaskWatchApp: App {
    // WCSession の有効化は ExtensionDelegate.applicationDidFinishLaunching で行う。
    // 裏起動では Scene が作られないことがあり、ここの @StateObject だけでは遅い。
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) private var delegate
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(session)
        }
    }
}

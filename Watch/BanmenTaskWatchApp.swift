import SwiftUI

@main
struct BanmenTaskWatchApp: App {
    // 起動と同時に WCSession を有効化する。
    // iPhone からの transferCurrentComplicationUserInfo で裏起動された時も、
    // ここで delegate が立つので受信できる。
    @StateObject private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(session)
        }
    }
}

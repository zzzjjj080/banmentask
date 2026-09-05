import SwiftUI

@main
struct BanmenTaskApp: App {
    @StateObject private var session = PhoneSession.shared

    init() {
        // BGTask の登録は起動完了前でないと拒否される
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}

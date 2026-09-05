import SwiftUI

@main
struct BanmenTaskApp: App {
    @StateObject private var session = PhoneSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}

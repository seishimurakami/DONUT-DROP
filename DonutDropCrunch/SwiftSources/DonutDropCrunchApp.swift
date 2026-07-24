import SwiftUI

@main
struct DonutDropCrunchApp: App {
    init() {
        GameCenterManager.shared.authenticatePlayer()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

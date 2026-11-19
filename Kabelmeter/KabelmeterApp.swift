import SwiftUI

@main
struct KabelmeterApp: App {
    @StateObject private var cableStore = CableStore()
    @StateObject private var fixtureStore = FixtureStore()
    @StateObject private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            RoomsScreen()
                .environmentObject(cableStore)
                .environmentObject(fixtureStore)
                .environmentObject(projectStore)
                .tint(Theme.accent)
        }
    }
}

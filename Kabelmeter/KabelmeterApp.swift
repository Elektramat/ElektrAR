import SwiftUI

@main
struct KabelmeterApp: App {
    @StateObject private var cableStore = CableStore()
    @StateObject private var fixtureStore = FixtureStore()
    @StateObject private var projectStore = ProjectStore()

    init() { BrandAppearance.apply() }

    var body: some Scene {
        WindowGroup {
            RoomsScreen()
                .environmentObject(cableStore)
                .environmentObject(fixtureStore)
                .environmentObject(projectStore)
                .tint(Theme.accent)
                // Light only, like the shop: dark mode turned every bar grey with blue on top.
                .preferredColorScheme(.light)
        }
    }
}

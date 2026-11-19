import SwiftUI

@main
struct KabelmeterApp: App {
    @StateObject private var cableStore = CableStore()
    @StateObject private var cartStore = CartStore()
    @StateObject private var fixtureStore = FixtureStore()

    var body: some Scene {
        WindowGroup {
            MeasureScreen()
                .environmentObject(cableStore)
                .environmentObject(cartStore)
                .environmentObject(fixtureStore)
                .tint(Theme.accent)
        }
    }
}

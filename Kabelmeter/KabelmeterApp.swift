import SwiftUI

@main
struct KabelmeterApp: App {
    @StateObject private var cableStore = CableStore()
    @StateObject private var cartStore = CartStore()
    @StateObject private var fixtureStore = FixtureStore()

    init() { BrandAppearance.apply() }

    var body: some Scene {
        WindowGroup {
            MeasureScreen()
                .environmentObject(cableStore)
                .environmentObject(cartStore)
                .environmentObject(fixtureStore)
                .tint(Theme.accent)
                // Light only, like the shop: dark mode turned every bar grey with blue on top.
                .preferredColorScheme(.light)
        }
    }
}

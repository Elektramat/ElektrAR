import SwiftUI

@main
struct KabelmeterApp: App {
    @StateObject private var cableStore = CableStore()
    @StateObject private var cartStore = CartStore()

    var body: some Scene {
        WindowGroup {
            MeasureScreen()
                .environmentObject(cableStore)
                .environmentObject(cartStore)
                .tint(Theme.accent)
        }
    }
}

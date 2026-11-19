import SwiftUI

extension View {
    /// A filled button in Elektramat blue (or another brand fill) with white text and icon.
    /// Use this instead of `.buttonStyle(.borderedProminent)` on a blue fill: the system picks
    /// the label color itself, and that may be black. Rule: never black text on a blue button.
    func brandProminentButton(_ fill: Color = Theme.accent) -> some View {
        buttonStyle(.borderedProminent)
            .tint(fill)
            .foregroundStyle(Theme.onAccent)
    }
}

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

/// − and + in Elektramat style, instead of the grey system Stepper: light grey buttons with
/// an ink icon; the pressed button turns solid Elektramat blue with a white icon. Disabled at
/// the end of the range (40 % opacity, DESIGN.md).
struct BrandStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var accessibilityName = "Waarde"

    var body: some View {
        HStack(spacing: 6) {
            button("minus", label: "Minder", disabled: value - step < range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            button("plus", label: "Meer", disabled: value + step > range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .sensoryFeedback(.increase, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func button(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.bold))
        }
        .buttonStyle(StepperButtonStyle())
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

private struct StepperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.onAccent : Theme.ink)
            .frame(width: 52, height: 40)
            .background(configuration.isPressed ? Theme.accent : Color(Theme.Token.black5),
                        in: RoundedRectangle(cornerRadius: Theme.buttonCorner))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

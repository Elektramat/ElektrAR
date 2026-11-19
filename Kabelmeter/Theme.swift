import SwiftUI
import UIKit

/// All colors, fonts and sizes in one place, based on the Elektramat design tokens
/// used on www.elektramat.nl (styles.min.css, 19 Nov 2026): primary blue for brand and
/// secondary actions, green for the main call to action ("in winkelwagen").
enum Theme {
    // Elektramat tokens (hex values from --color-* on elektramat.nl)
    enum Token {
        static let primary = UIColor(hex: 0x196CAE)       // --color-primary
        static let primary110 = UIColor(hex: 0x17619D)    // --color-primary-110
        static let primary10 = UIColor(hex: 0xE8F0F7)     // --color-primary-10
        static let secondary = UIColor(hex: 0x34BBDA)     // --color-secondary
        static let success = UIColor(hex: 0x70CC0A)       // --color-success (btn-cta)
        static let success110 = UIColor(hex: 0x65B809)    // --color-success-110
        static let warning = UIColor(hex: 0xF7A111)       // --color-warning
        static let alert = UIColor(hex: 0xE53030)         // --color-alert
        static let black75 = UIColor(hex: 0x404040)       // --color-black-75
        static let black25 = UIColor(hex: 0xBFBFBF)       // --color-black-25
        static let black5 = UIColor(hex: 0xF2F2F2)        // --color-black-5
        static let black15 = UIColor(hex: 0xD9D9D9)       // --color-black-15
        static let ink = UIColor(hex: 0x1A1A1A)
    }

    // Surfaces. The app is light only, like the shop: white cards with a soft shadow on the
    // camera image, brand blue for icons and selection, never blue on grey.
    static let surface = Color.white
    static let ink = Color(Token.ink)
    static let inkSecondary = Color(Token.black75)
    static let iconDisabled = Color(Token.black25)
    static let hairline = Color(Token.black15)

    // Colors
    static let accent = Color(Token.primary)
    static let onAccent = Color.white
    /// The main call to action, like the green "in winkelwagen" button on the shop.
    static let cta = Color(Token.success110)
    static let brandSurface = Color(Token.primary)
    static let brandSurfaceSoft = Color(Token.primary10)
    static let sampleBadge = Color(Token.black75)
    static let warning = Color(Token.warning)
    static let alert = Color(Token.alert)
    static let success = Color(Token.success)
    static let secondaryButton = Color(Token.black25)
    static let crosshairActive = Color.white
    static let crosshairInactive = Color.white.opacity(0.35)
    static let simulatedBackground = Color(white: 0.12)
    static let simulatedWall = Color(white: 0.22)
    /// Behind the switch previews: a light wall tone, so white and black switches both read.
    static let previewBackground = Color(Token.black5)

    // AR entities: the light brand blue stands out on a camera image.
    static let arPoint = UIColor.white
    static let arSegment = Token.secondary
    static let arPreview = Token.secondary.withAlphaComponent(0.6)
    static let arGuide = UIColor.white.withAlphaComponent(0.5)
    /// Cables that are already in the cart.
    static let arRun = UIColor.systemTeal
    /// Dotted height line from the crosshair to the floor.
    static let arHeight = UIColor.systemYellow
    static let run = Color.teal
    static let height = Color.yellow

    // Sizes (radius-xl = 0.75rem, radius-2xl = 1rem on the shop)
    static let spacing: CGFloat = 12
    /// Inner padding of the bottom bars (price and placing), so content keeps off the rounded edge.
    static let barPadding: CGFloat = 20
    static let corner: CGFloat = 16
    static let buttonCorner: CGFloat = 12
    static let tapTarget: CGFloat = 56
    static let addButton: CGFloat = tapTarget
    static let crosshair: CGFloat = 28

    // Fonts. The shop uses Hellix (headings) and Avenir LT Std (body). Both are licensed
    // and not in the app bundle, so the app uses the system font with matching weights.
    static func branded(_ style: Font.TextStyle) -> Font { .system(style, design: .default).weight(.heavy) }
    static let priceFont = Font.system(.largeTitle, design: .default).weight(.heavy)
    static let lengthFont = Font.system(.title3, design: .default).weight(.semibold)
    static let labelFont = Font.footnote
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A white card on the camera image: solid white, soft shadow, dark text.
    func surface<S: InsettableShape>(_ shape: S) -> some View {
        self
            .foregroundStyle(Theme.ink)
            .background {
                // Shadow on the card only, not on the text inside it.
                shape.fill(Theme.surface)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

/// For every custom button (cards, chips, round icon buttons): visible and felt on touch.
/// Pressed: shrinks to 90%, darkens a little and gives a light tap, so the user knows the
/// button reacted before anything else changes. No automatic dimming when disabled: the
/// label keeps its full colors, so a white card stays white on the camera image.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

enum BrandAppearance {
    /// Segmented controls in brand blue with white text, instead of grey system segments.
    @MainActor static func apply() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = Theme.Token.primary
        segmented.backgroundColor = .white
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white,
                                          .font: UIFont.systemFont(ofSize: 15, weight: .semibold)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: Theme.Token.ink,
                                          .font: UIFont.systemFont(ofSize: 15, weight: .medium)], for: .normal)
    }
}

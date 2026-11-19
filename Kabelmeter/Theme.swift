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
    }

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
    static let secondaryButton = Color(Token.black25).opacity(0.6)
    static let crosshairActive = Color.white
    static let crosshairInactive = Color.white.opacity(0.35)
    static let simulatedBackground = Color(white: 0.12)
    static let simulatedWall = Color(white: 0.22)

    // AR entities: the light brand blue stands out on a camera image.
    static let arPoint = UIColor.white
    static let arSegment = Token.secondary
    static let arPreview = Token.secondary.withAlphaComponent(0.6)
    static let arGuide = UIColor.white.withAlphaComponent(0.5)

    // Sizes (radius-xl = 0.75rem, radius-2xl = 1rem on the shop)
    static let spacing: CGFloat = 12
    static let corner: CGFloat = 16
    static let buttonCorner: CGFloat = 12
    static let tapTarget: CGFloat = 56
    static let addButton: CGFloat = 80
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

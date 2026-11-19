import SwiftUI
import UIKit

/// All colors, fonts and sizes in one place. Placeholder palette: swap these
/// values when the team supplies design tokens.
enum Theme {
    // Colors
    static let accent = Color.orange
    static let onAccent = Color.white
    static let sampleBadge = Color.purple
    static let warning = Color.yellow
    static let secondaryButton = Color.gray.opacity(0.35)
    static let crosshairActive = Color.white
    static let crosshairInactive = Color.white.opacity(0.35)
    static let simulatedBackground = Color(white: 0.12)
    static let simulatedWall = Color(white: 0.22)
    /// Behind the switch previews: a light wall tone, so white and black switches both read.
    static let previewBackground = Color(white: 0.86)

    // AR entities
    static let arPoint = UIColor.white
    static let arSegment = UIColor.systemOrange
    static let arPreview = UIColor.systemOrange.withAlphaComponent(0.6)
    static let arGuide = UIColor.white.withAlphaComponent(0.5)

    // Sizes
    static let spacing: CGFloat = 12
    static let corner: CGFloat = 18
    static let tapTarget: CGFloat = 56
    static let addButton: CGFloat = 80
    static let crosshair: CGFloat = 28

    // Fonts
    static let priceFont = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let lengthFont = Font.system(.title3, design: .rounded).weight(.semibold)
    static let labelFont = Font.footnote
}

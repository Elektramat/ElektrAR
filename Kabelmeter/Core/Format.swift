import Foundation

/// Dutch number formatting: comma decimals and euros.
nonisolated enum Format {
    static let locale = Locale(identifier: "nl_NL")

    /// "7,4 m"
    static func meters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " m"
    }

    /// "10 m" or "10,5 m": whole meters without decimals.
    static func orderLength(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " m"
    }

    /// "100 m + 25 m" for rolls, "10 m" for cut-to-length.
    static func pieces(_ pieces: [Double]) -> String {
        pieces.map(orderLength).joined(separator: " + ")
    }

    /// "€ 9,90"
    static func euro(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(locale))
    }

    /// "15%"
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

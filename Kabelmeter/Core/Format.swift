import Foundation

/// Dutch number formatting: comma decimals and euros.
nonisolated enum Format {
    static let locale = Locale(identifier: "nl_NL")

    /// "7,4 m"
    static func meters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " m"
    }

    /// "1,05 m": heights on a wall, to the centimeter.
    static func height(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale)) + " m"
    }

    /// "3" or "2,5": a cart quantity.
    static func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// "10 m" or "10,5 m": whole meters without decimals.
    static func orderLength(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " m"
    }

    /// "100 m + 25 m" for rolls, "10 m" for cut-to-length.
    static func pieces(_ pieces: [Double]) -> String {
        pieces.map(orderLength).joined(separator: " + ")
    }

    /// "2 × 50 m + 1 × 25 m": rolls grouped by length, longest first.
    static func rolls(_ pieces: [Double]) -> String {
        Dictionary(grouping: pieces, by: { $0 }).sorted { $0.key > $1.key }
            .map { "\($0.value.count) × \(orderLength($0.key))" }.joined(separator: " + ")
    }

    /// "1 kabel", "3 kabels": a count with the right Dutch word.
    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
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

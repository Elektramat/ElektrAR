import Foundation

/// The result of pricing one measurement for one cable.
nonisolated struct Quote: Equatable, Sendable {
    /// Measured route length in meters.
    let measured: Double
    /// measured * (1 + reserve) + connection allowance, in meters.
    let required: Double
    /// Lengths to order. One entry for `perMeter`, one entry per roll for `fixedLengths`.
    let pieces: [Double]
    /// Sum of `pieces`, in meters.
    let billedLength: Double
    /// billedLength * pricePerMeter, rounded to cents.
    let price: Double
}

/// Pure pricing rules. All numbers are meters (Double) and euros.
nonisolated enum PricingCalculator {
    static let defaultReserve = 0.15
    static let reserveRange: ClosedRange<Double> = 0...0.30
    /// 1 m at each end of the route.
    static let connectionAllowance = 2.0
    /// Absorbs floating point noise, so 10.000000001 m does not become 11 m.
    private static let tolerance = 1e-6

    static func requiredLength(measured: Double, reserve: Double,
                               allowance: Double = connectionAllowance) -> Double {
        let reserve = min(max(reserve, reserveRange.lowerBound), reserveRange.upperBound)
        return max(0, measured) * (1 + reserve) + allowance
    }

    /// Returns nil when nothing is measured yet (the UI then shows the price per meter).
    static func quote(for cable: Cable, measured: Double, reserve: Double,
                      allowance: Double = connectionAllowance) -> Quote? {
        guard measured.isFinite, measured > 0 else { return nil }
        let required = requiredLength(measured: measured, reserve: reserve, allowance: allowance)
        let pieces = billedPieces(required: required, sales: cable.sales)
        let billed = pieces.reduce(0, +)
        return Quote(measured: measured, required: required, pieces: pieces,
                     billedLength: billed, price: roundToCents(billed * cable.pricePerMeter))
    }

    static func billedPieces(required: Double, sales: SalesUnit) -> [Double] {
        switch sales {
        case let .perMeter(step, minimum):
            let steps = (required / step - tolerance).rounded(.up)
            return [max(minimum, steps * step)]
        case let .fixedLengths(lengths):
            return cheapestRolls(required: required, lengths: lengths)
        }
    }

    /// The combination of rolls with the smallest total length that covers `required`
    /// (price is per meter, so shortest total = cheapest). Ties: fewest rolls.
    /// Exact search on whole centimeters; falls back to "largest rolls + smallest that
    /// covers the rest" for absurd lengths.
    static func cheapestRolls(required: Double, lengths: [Double]) -> [Double] {
        let sorted = Array(Set(lengths.filter { $0 > 0 })).sorted()
        guard let largest = sorted.last else { return [] }
        if let single = sorted.first(where: { $0 >= required - tolerance }) {
            return [single]
        }

        let unit = 100.0 // centimeters
        let target = Int((required * unit - tolerance).rounded(.up))
        let sizes = sorted.map { Int(($0 * unit).rounded()) }
        let limit = target + sizes.max()!
        guard limit <= 2_000_000 else { return greedyRolls(required: required, sorted: sorted, largest: largest) }

        // fewest[s] = fewest rolls that sum exactly to s centimeters, last[s] = roll used last.
        var fewest = [Int](repeating: .max, count: limit + 1)
        var last = [Int](repeating: -1, count: limit + 1)
        fewest[0] = 0
        for s in 1...limit {
            for (i, size) in sizes.enumerated() where size <= s && fewest[s - size] != .max {
                if fewest[s - size] + 1 < fewest[s] {
                    fewest[s] = fewest[s - size] + 1
                    last[s] = i
                }
            }
        }
        guard var s = (target...limit).first(where: { fewest[$0] != .max }) else {
            return greedyRolls(required: required, sorted: sorted, largest: largest)
        }
        var pieces: [Double] = []
        while s > 0 {
            let i = last[s]
            pieces.append(sorted[i])
            s -= sizes[i]
        }
        return pieces.sorted(by: >)
    }

    private static func greedyRolls(required: Double, sorted: [Double], largest: Double) -> [Double] {
        let fullCount = Int((required / largest - tolerance).rounded(.down))
        var pieces = Array(repeating: largest, count: fullCount)
        let rest = required - Double(fullCount) * largest
        if rest > tolerance {
            pieces.append(sorted.first(where: { $0 >= rest - tolerance }) ?? largest)
        }
        return pieces
    }

    static func roundToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

import XCTest
@testable import KabelmeterCore

/// rollPlan and cheapestRolls search in steps of the greatest common divisor of the roll
/// lengths instead of whole centimeters (19 Nov 2026, for speed). These tests keep a copy of
/// the old centimeter search and prove that the answer is the same. On 19 Nov 2026 this ran
/// once at 0,137 m steps up to 500 m for every roll set below with no difference; the steps
/// here are coarser so the suite stays fast (the reference search is slow in debug).
final class RollPlanEquivalenceTests: XCTestCase {
    private func roll(_ length: Double, _ price: Double) -> CableRoll {
        CableRoll(lengthM: length, sku: "R\(length)", price: price,
                  productUrl: URL(string: "https://www.elektramat.nl/")!, shopProductId: nil, stock: nil)
    }

    private let rollSets: [[(Double, Double)]] = [
        [(100, 208.77), (50, 117.66), (25, 64.51)],      // Snelflex 3x2,5 today
        [(100, 150), (50, 117.66), (25, 64.51)],         // cheap big roll
        [(100, 89.0), (25, 30.0), (10, 15.5)],           // gcd 5 m
        [(33.3, 50), (12.5, 22)],                        // odd lengths, gcd 0,1 m
        [(50, 80)],                                      // one size
    ]

    func testRollPlanMatchesTheCentimeterSearch() {
        for set in rollSets {
            let rolls = set.map { roll($0.0, $0.1) }
            var required = 0.0
            while required <= 320 {
                let new = PricingCalculator.rollPlan(required: required, rolls: rolls).map(\.lengthM)
                let old = Self.centimeterRollPlan(required: required, rolls: rolls).map(\.lengthM)
                XCTAssertEqual(new, old, "rolls \(set.map(\.0)), required \(required)")
                if new != old { return }
                required = (required + 3.13).rounded(toPlaces: 3)
            }
        }
    }

    func testRollPlanMatchesOnExactRollBoundaries() {
        let rolls = rollSets[0].map { roll($0.0, $0.1) }
        for required in [24.999, 25, 25.0000001, 25.001, 50, 74.99, 75, 99.9999999, 100, 100.01, 249.999, 250] {
            XCTAssertEqual(PricingCalculator.rollPlan(required: required, rolls: rolls).map(\.lengthM),
                           Self.centimeterRollPlan(required: required, rolls: rolls).map(\.lengthM),
                           "required \(required)")
        }
    }

    func testCheapestRollsMatchesTheCentimeterSearch() {
        for lengths in [[10.0, 25, 50, 100], [25, 50, 100], [100], [12.5, 33.3]] {
            var required = 0.1
            while required <= 320 {
                XCTAssertEqual(PricingCalculator.cheapestRolls(required: required, lengths: lengths),
                               Self.centimeterCheapestRolls(required: required, lengths: lengths),
                               "lengths \(lengths), required \(required)")
                required = (required + 6.7).rounded(toPlaces: 3)
            }
        }
    }

    func testRollPlanIsFast() {
        let rolls = rollSets[0].map { roll($0.0, $0.1) }
        let start = Date()
        for i in 0..<200 { _ = PricingCalculator.rollPlan(required: 250 + Double(i) * 0.37, rolls: rolls) }
        let ms = Date().timeIntervalSince(start) / 200 * 1000
        print("rollPlan for ~250-320 m: \(String(format: "%.4f", ms)) ms per call")
        XCTAssertLessThan(ms, 1.0, "rollPlan should stay well under a millisecond, also in debug")
    }

    // MARK: The old centimeter search, kept as the reference

    private static let tolerance = 1e-6

    static func centimeterRollPlan(required: Double, rolls: [CableRoll]) -> [CableRoll] {
        let options = rolls.filter { $0.lengthM > 0 && $0.price >= 0 }
        guard !options.isEmpty, required > tolerance else { return [] }
        let sizes = options.map { Int(($0.lengthM * 100).rounded()) }
        let costs = options.map { Int(($0.price * 100).rounded()) }
        let target = Int((required * 100 - tolerance).rounded(.up))
        let limit = target + (sizes.max() ?? 0)
        var cost = [Int](repeating: .max, count: limit + 1)
        var count = [Int](repeating: .max, count: limit + 1)
        var last = [Int](repeating: -1, count: limit + 1)
        cost[0] = 0; count[0] = 0
        for s in 1...limit {
            for (i, size) in sizes.enumerated() where size <= s && cost[s - size] != .max {
                let c = cost[s - size] + costs[i], n = count[s - size] + 1
                if c < cost[s] || (c == cost[s] && n < count[s]) { cost[s] = c; count[s] = n; last[s] = i }
            }
        }
        guard var s = (target...limit).filter({ cost[$0] != .max })
            .min(by: { (cost[$0], count[$0], $0) < (cost[$1], count[$1], $1) }) else { return [] }
        var plan: [CableRoll] = []
        while s > 0 { let i = last[s]; plan.append(options[i]); s -= sizes[i] }
        return plan.sorted { $0.lengthM > $1.lengthM }
    }

    static func centimeterCheapestRolls(required: Double, lengths: [Double]) -> [Double] {
        let sorted = Array(Set(lengths.filter { $0 > 0 })).sorted()
        guard !sorted.isEmpty else { return [] }
        if let single = sorted.first(where: { $0 >= required - tolerance }) { return [single] }
        let target = Int((required * 100 - tolerance).rounded(.up))
        let sizes = sorted.map { Int(($0 * 100).rounded()) }
        let limit = target + sizes.max()!
        var fewest = [Int](repeating: .max, count: limit + 1)
        var last = [Int](repeating: -1, count: limit + 1)
        fewest[0] = 0
        for s in 1...limit {
            for (i, size) in sizes.enumerated() where size <= s && fewest[s - size] != .max {
                if fewest[s - size] + 1 < fewest[s] { fewest[s] = fewest[s - size] + 1; last[s] = i }
            }
        }
        guard var s = (target...limit).first(where: { fewest[$0] != .max }) else { return [] }
        var pieces: [Double] = []
        while s > 0 { let i = last[s]; pieces.append(sorted[i]); s -= sizes[i] }
        return pieces.sorted(by: >)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}

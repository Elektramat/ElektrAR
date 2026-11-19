import XCTest
@testable import KabelmeterCore

final class PricingCalculatorTests: XCTestCase {
    private func cable(_ sales: SalesUnit, price: Double = 1.0) -> Cable {
        Cable(id: "t", sku: "T", name: "Test", crossSection: "3x1,5 mm²", use: "Test",
              pricePerMeter: price, sales: sales, stock: "Op voorraad", imageUrl: nil,
              productUrl: URL(string: "https://www.elektramat.nl")!, isSample: true)
    }

    // MARK: required length

    func testRequiredLengthAddsReserveAndAllowance() {
        XCTAssertEqual(PricingCalculator.requiredLength(measured: 10, reserve: 0.15), 13.5, accuracy: 1e-9)
    }

    func testReserveIsClampedToRange() {
        XCTAssertEqual(PricingCalculator.requiredLength(measured: 10, reserve: 0.9), 15, accuracy: 1e-9)
        XCTAssertEqual(PricingCalculator.requiredLength(measured: 10, reserve: -1), 12, accuracy: 1e-9)
    }

    // MARK: zero, invalid

    func testZeroMeasuredGivesNoQuote() {
        XCTAssertNil(PricingCalculator.quote(for: cable(.perMeter(step: 1, minimum: 1)), measured: 0, reserve: 0.15))
    }

    func testNegativeAndNonFiniteGiveNoQuote() {
        let c = cable(.perMeter(step: 1, minimum: 1))
        XCTAssertNil(PricingCalculator.quote(for: c, measured: -3, reserve: 0.15))
        XCTAssertNil(PricingCalculator.quote(for: c, measured: .nan, reserve: 0.15))
        XCTAssertNil(PricingCalculator.quote(for: c, measured: .infinity, reserve: 0.15))
    }

    // MARK: perMeter

    func testPerMeterExactlyOnStepIsNotRoundedUp() {
        // 8 * 1.0 + 2 = 10 exactly
        let q = PricingCalculator.quote(for: cable(.perMeter(step: 1, minimum: 1), price: 0.99), measured: 8, reserve: 0)
        XCTAssertEqual(q?.pieces, [10])
        XCTAssertEqual(q?.price, 9.90)
    }

    func testPerMeterFloatingNoiseOnStepIsNotRoundedUp() {
        // 7.4 * 1.15 + 2 = 10.51 → 11; and 0.1+0.2 style noise must not push 10 to 11
        let pieces = PricingCalculator.billedPieces(required: 10.000000001, sales: .perMeter(step: 1, minimum: 1))
        XCTAssertEqual(pieces, [10])
    }

    func testPerMeterJustOverStepRoundsUp() {
        let pieces = PricingCalculator.billedPieces(required: 10.01, sales: .perMeter(step: 1, minimum: 1))
        XCTAssertEqual(pieces, [11])
    }

    func testPerMeterHalfMeterStep() {
        let pieces = PricingCalculator.billedPieces(required: 3.2, sales: .perMeter(step: 0.5, minimum: 1))
        XCTAssertEqual(pieces, [3.5])
    }

    func testPerMeterMinimumOrder() {
        let pieces = PricingCalculator.billedPieces(required: 2.3, sales: .perMeter(step: 1, minimum: 5))
        XCTAssertEqual(pieces, [5])
    }

    func testPerMeterExampleFromBrief() {
        // Gemeten 7,4 m, 15% reserve, 2 m allowance → 10.51 m → 11 m
        let q = PricingCalculator.quote(for: cable(.perMeter(step: 1, minimum: 1), price: 0.99), measured: 7.4, reserve: 0.15)
        XCTAssertEqual(q?.billedLength, 11)
        XCTAssertEqual(q?.price, 10.89)
    }

    // MARK: fixedLengths

    func testFixedLengthsSmallestSingleThatFits() {
        let pieces = PricingCalculator.billedPieces(required: 13.5, sales: .fixedLengths([10, 25, 50, 100]))
        XCTAssertEqual(pieces, [25])
    }

    func testFixedLengthsExactlyARollLength() {
        let pieces = PricingCalculator.billedPieces(required: 50, sales: .fixedLengths([100, 10, 50, 25]))
        XCTAssertEqual(pieces, [50])
    }

    func testFixedLengthsLargerThanLargestRoll() {
        // 100 + 10 + 10 = 120 m is less cable than 100 + 25 = 125 m.
        let pieces = PricingCalculator.billedPieces(required: 120, sales: .fixedLengths([10, 25, 50, 100]))
        XCTAssertEqual(pieces, [100, 10, 10])
    }

    func testFixedLengthsExactMultipleOfLargest() {
        let pieces = PricingCalculator.billedPieces(required: 200, sales: .fixedLengths([10, 25, 50, 100]))
        XCTAssertEqual(pieces, [100, 100])
    }

    func testFixedLengthsSingleRollSize() {
        let pieces = PricingCalculator.billedPieces(required: 130, sales: .fixedLengths([100]))
        XCTAssertEqual(pieces, [100, 100])
    }

    func testFixedLengthsPrice() {
        let q = PricingCalculator.quote(for: cable(.fixedLengths([10, 25, 50, 100]), price: 0.79), measured: 10, reserve: 0.15)
        XCTAssertEqual(q?.pieces, [25])
        XCTAssertEqual(q?.billedLength, 25)
        XCTAssertEqual(q?.price, 19.75)
    }

    // MARK: large values

    func testLargeValues() {
        let q = PricingCalculator.quote(for: cable(.perMeter(step: 1, minimum: 1), price: 1.49), measured: 1000, reserve: 0.15)
        XCTAssertEqual(q?.billedLength, 1152)
        XCTAssertEqual(q?.price, 1716.48)

        // Cheapest: 1155 m, not "11 x 100 + another 100" (= 1200 m).
        let rolls = PricingCalculator.billedPieces(required: 1152, sales: .fixedLengths([10, 25, 50, 100]))
        XCTAssertEqual(rolls.reduce(0, +), 1155)
    }

    func testFixedLengthsPicksCheaperCombinationThanGreedy() {
        // Greedy would take 100 + 100 = 200 m; 100 + 50 = 150 m covers 140 m.
        let pieces = PricingCalculator.billedPieces(required: 140, sales: .fixedLengths([25, 50, 100]))
        XCTAssertEqual(pieces, [100, 50])
    }

    func testFixedLengthsHugeLengthFallsBackWithoutHanging() {
        let pieces = PricingCalculator.billedPieces(required: 50_000, sales: .fixedLengths([10, 100]))
        XCTAssertEqual(pieces.reduce(0, +), 50_000)
    }

    // MARK: formatting

    func testDutchFormatting() {
        XCTAssertEqual(Format.meters(7.4), "7,4 m")
        XCTAssertEqual(Format.orderLength(10), "10 m")
        XCTAssertEqual(Format.orderLength(3.5), "3,5 m")
        XCTAssertEqual(Format.pieces([100, 25]), "100 m + 25 m")
        XCTAssertEqual(Format.percent(0.15), "15%")
        let euro = Format.euro(9.9)
        XCTAssertTrue(euro.contains("€"))
        XCTAssertTrue(euro.contains("9,90"))
    }
}

final class RollPlanTests: XCTestCase {
    private func roll(_ length: Double, _ price: Double) -> CableRoll {
        CableRoll(lengthM: length, sku: "R\(Int(length))", price: price,
                  productUrl: URL(string: "https://www.elektramat.nl/")!, shopProductId: Int(length), stock: nil)
    }

    /// The Snelflex 3x2,5 rolls: a shorter roll costs more per meter.
    private let rolls: [CableRoll] = [(100.0, 208.77), (50, 117.66), (25, 64.51)].map {
        CableRoll(lengthM: $0.0, sku: "R\(Int($0.0))", price: $0.1,
                  productUrl: URL(string: "https://www.elektramat.nl/")!, shopProductId: Int($0.0), stock: nil)
    }

    private func plan(_ required: Double) -> [Double] {
        PricingCalculator.rollPlan(required: required, rolls: rolls).map(\.lengthM)
    }

    func testSmallLengthTakesTheShortestRoll() {
        XCTAssertEqual(plan(5.2), [25])
        XCTAssertEqual(plan(25), [25])
    }

    func testJustOverARollTakesTheCheapestCover() {
        XCTAssertEqual(plan(25.1), [50])   // 117,66 beats 25+25 (129,02)
        XCTAssertEqual(plan(60), [50, 25]) // 182,17 beats 100 (208,77)
    }

    func testPrefersTheBigRollWhenItIsCheaper() {
        XCTAssertEqual(plan(80), [100])    // 208,77 beats 50+25+25 (246,68)
        XCTAssertEqual(plan(100), [100])
    }

    func testSeveralRolls() {
        XCTAssertEqual(plan(150), [100, 50])
        XCTAssertEqual(plan(210), [100, 100, 25].sorted(by: >))
    }

    func testCheaperThanTheShortestTotalWhenPricesDiffer() {
        // Shortest cover of 70 m is 50+25 = 75 m (182,17); a 100 m roll is longer and dearer here.
        XCTAssertEqual(plan(70), [50, 25])
        // But with a cheap 100 m roll the longer combination wins.
        let cheap100 = [roll(100, 150), roll(50, 117.66), roll(25, 64.51)]
        XCTAssertEqual(PricingCalculator.rollPlan(required: 70, rolls: cheap100).map(\.lengthM), [100])
    }

    func testNothingNeededNoRolls() {
        XCTAssertTrue(PricingCalculator.rollPlan(required: 0, rolls: rolls).isEmpty)
        XCTAssertTrue(PricingCalculator.rollPlan(required: 10, rolls: []).isEmpty)
    }

    func testQuoteUsesTheRollPrices() throws {
        let cable = Cable(id: "c", sku: "c", name: "Snelflex", crossSection: "3x2,5 mm²", use: "x",
                          pricePerMeter: 2.0877, sales: .fixedLengths([100, 50, 25]), stock: "x", imageUrl: nil,
                          productUrl: URL(string: "https://www.elektramat.nl/")!, isSample: false, rolls: rolls)
        let quote = try XCTUnwrap(PricingCalculator.quote(for: cable, measured: 10, reserve: 0.15))
        XCTAssertEqual(quote.required, 13.5, accuracy: 1e-9)
        XCTAssertEqual(quote.pieces, [25])
        XCTAssertEqual(quote.price, 64.51)
        XCTAssertEqual(Format.rolls([100, 50, 50, 25]), "1 × 100 m + 2 × 50 m + 1 × 25 m")
    }
}

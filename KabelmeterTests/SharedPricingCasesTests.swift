import XCTest
@testable import KabelmeterCore

/// Runs shared/pricing-cases.json, the same file the PWA tests run, so the iPhone app
/// and the web app cannot drift apart on quantity or price.
final class SharedPricingCasesTests: XCTestCase {
    private struct Cases: Decodable {
        struct Piece: Decodable { let required: Double; let sales: SalesUnit; let pieces: [Double] }
        struct Expected: Decodable { let billedLength: Double; let price: Double }
        struct QuoteCase: Decodable {
            let measured: Double; let reserve: Double; let pricePerMeter: Double
            let sales: SalesUnit; let quote: Expected?
        }
        let pieces: [Piece]
        let quotes: [QuoteCase]
    }

    private func load() throws -> Cases {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/pricing-cases.json")
        return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }

    func testPieces() throws {
        for c in try load().pieces {
            XCTAssertEqual(PricingCalculator.billedPieces(required: c.required, sales: c.sales), c.pieces,
                           "required \(c.required)")
        }
    }

    func testQuotes() throws {
        for c in try load().quotes {
            let cable = Cable(id: "t", sku: "T", name: "T", crossSection: "x", use: "x", pricePerMeter: c.pricePerMeter,
                              sales: c.sales, stock: "x", imageUrl: nil,
                              productUrl: URL(string: "https://www.elektramat.nl")!, isSample: true)
            let q = PricingCalculator.quote(for: cable, measured: c.measured, reserve: c.reserve)
            XCTAssertEqual(q?.billedLength, c.quote?.billedLength, "measured \(c.measured)")
            XCTAssertEqual(q?.price, c.quote?.price, "measured \(c.measured)")
        }
    }
}

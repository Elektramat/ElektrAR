import Foundation

/// One elektramat.nl product that is part of a fixture (frame, rocker, socket insert, ...).
nonisolated struct FixturePart: Codable, Equatable, Sendable {
    let role: String
    let sku: String
    let description: String
    let price: Double?
    let productUrl: URL
}

/// A switch or socket that can be placed on a wall, with its 3D model and parts.
/// Built from assets/sku_mapping.csv by scripts/fixtures_to_json.py.
nonisolated struct Fixture: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let brand: String
    let line: String
    let colour: String
    /// "schakelaar" or "stopcontact".
    let product: String
    /// Full product name, e.g. "Wipschakelaar 1-voudig".
    let productName: String
    /// "inbouw" (flush) or "opbouw" (surface mounted).
    let mounting: String
    /// Model file name in the bundle, without ".usdz".
    let model: String
    /// False when not every part can be ordered on elektramat.nl.
    let complete: Bool
    /// Price of the complete set incl. VAT; nil when incomplete.
    let price: Double?
    let parts: [FixturePart]
    let note: String?
    /// Frame width and height in mm, from the model manifest.
    let frameMM: [Double]?
    /// Distance from the wall to the front in mm.
    let depthMM: Double?

    var title: String {
        let base = product == "stopcontact" ? "Stopcontact" : "Schakelaar"
        return mounting == "opbouw" ? "\(base) opbouw" : base
    }

    var colourName: String { colour.replacingOccurrences(of: "-", with: " ") }

    var subtitle: String { "\(brand) \(line) · \(colourName)" }
}

nonisolated enum FixtureCatalog {
    static func decode(_ data: Data) throws -> [Fixture] {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
        guard Set(fixtures.map(\.id)).count == fixtures.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Duplicate fixture id"))
        }
        guard fixtures.allSatisfy({ ($0.price ?? 0) >= 0 && (!$0.complete || $0.price != nil) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad fixture price"))
        }
        return fixtures
    }
}

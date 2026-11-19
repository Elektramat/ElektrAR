import Foundation

/// How a cable is sold. The real sales units are still an open question,
/// so everything that depends on them lives in `PricingCalculator`.
nonisolated enum SalesUnit: Equatable, Sendable {
    /// Cut to length: round up to a multiple of `step` meters, at least `minimum` meters.
    case perMeter(step: Double, minimum: Double)
    /// Only sold as fixed lengths (rolls), in meters.
    case fixedLengths([Double])
}

nonisolated extension SalesUnit: Codable {
    private enum CodingKeys: String, CodingKey { case type, step, minimum, lengthsM }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "perMeter":
            let step = try c.decode(Double.self, forKey: .step)
            let minimum = try c.decodeIfPresent(Double.self, forKey: .minimum) ?? 0
            guard step > 0, minimum >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .step, in: c,
                    debugDescription: "perMeter needs step > 0 and minimum >= 0")
            }
            self = .perMeter(step: step, minimum: minimum)
        case "fixedLengths":
            let lengths = try c.decode([Double].self, forKey: .lengthsM)
            guard !lengths.isEmpty, lengths.allSatisfy({ $0 > 0 }) else {
                throw DecodingError.dataCorruptedError(forKey: .lengthsM, in: c,
                    debugDescription: "fixedLengths needs at least one length > 0")
            }
            self = .fixedLengths(lengths)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown sales type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .perMeter(step, minimum):
            try c.encode("perMeter", forKey: .type)
            try c.encode(step, forKey: .step)
            try c.encode(minimum, forKey: .minimum)
        case let .fixedLengths(lengths):
            try c.encode("fixedLengths", forKey: .type)
            try c.encode(lengths, forKey: .lengthsM)
        }
    }
}

/// One roll size of a cable that the shop sells as separate roll products. A shorter roll costs
/// more per meter, so each roll has its own price, article number and shop product id.
nonisolated struct CableRoll: Codable, Equatable, Sendable {
    let lengthM: Double
    let sku: String
    /// Price of the whole roll incl. VAT.
    let price: Double
    let productUrl: URL
    let shopProductId: Int?
    let stock: String?
}

nonisolated struct Cable: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sku: String
    let name: String
    let crossSection: String
    let use: String
    let pricePerMeter: Double
    let sales: SalesUnit
    let stock: String
    let imageUrl: URL?
    let productUrl: URL
    let isSample: Bool
    /// The id the shop's add-to-cart form posts (not the SKU). Lets the app add to the shop
    /// cart without loading the product page. Optional: CSV data may not have it.
    var shopProductId: Int? = nil
    /// Cables sold as rolls of several lengths: the options, each with its own price. Then
    /// `sales` is `fixedLengths` with the same lengths and `pricePerMeter` is the cheapest one.
    var rolls: [CableRoll]? = nil

    /// True when the shop sells this cable as roll products.
    var hasRolls: Bool { !(rolls ?? []).isEmpty }
}

nonisolated enum CableCatalog {
    static func decode(_ data: Data) throws -> [Cable] {
        let cables = try JSONDecoder().decode([Cable].self, from: data)
        let ids = Set(cables.map(\.id))
        guard ids.count == cables.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Duplicate cable id"))
        }
        guard cables.allSatisfy({ $0.pricePerMeter >= 0 }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Negative price"))
        }
        guard cables.allSatisfy({ ($0.rolls ?? []).allSatisfy { $0.lengthM > 0 && $0.price >= 0 } }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad roll"))
        }
        return cables
    }
}

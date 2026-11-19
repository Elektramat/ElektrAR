import Foundation

/// One line of the shared shopping list: meters of a cable, or pieces of a switch or socket
/// part (by its Elektramat code), added up over all rooms.
nonisolated struct BillLine: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case cable
        case part
    }

    let kind: Kind
    /// Cable id for a cable, Elektramat code (sku) for a part.
    let productId: String
    let sku: String
    let name: String
    /// Cross-section for a cable, e.g. "Busch-Jaeger future linear · studiowit" for a part.
    let detail: String
    /// Price per meter (cable) or per piece (part), incl. VAT.
    let unitPrice: Double
    /// Meters to order (cable, rounded to how it is sold) or pieces (part).
    var quantity: Double
    /// Cable rolls or cut lengths, e.g. [25, 10]; empty for parts.
    var pieces: [Double]
    let productUrl: URL
    let isSample: Bool
    /// Names of the rooms this line comes from.
    var rooms: [String]

    var id: String { "\(kind.rawValue):\(productId)" }
    var linePrice: Double { PricingCalculator.roundToCents(quantity * unitPrice) }
}

/// The shared shopping list is not kept separately: it is worked out from the rooms, so it
/// always matches what is designed.
///
/// TODO(open question): a real webshop cart. Tried on 19 Nov 2026: the Elektramat MCP server
/// (https://mcp.elektramat.nl/mcp, no login) has `cable_create_order(productId, amount, presetId)`,
/// but without a login it only returns "https://www.elektramat.nl/checkout/cart" with no cart id,
/// token or cookie, so the browser sees an empty cart. With an OAuth login it may land in the
/// customer's own cart, but the server only accepts redirect URIs of known assistants and
/// localhost; an iOS app needs Elektramat to allow its redirect. Ask the MCP team for that, or
/// for a cart deep link. Also still open: how cable is sold (per meter, per roll, cut to length)
/// and whether decimal quantities are allowed.
nonisolated enum Bill {
    /// Shopping list for `projects`. Cable: per cable type the measured length of every cable plus
    /// reserve and connection allowance (per cable), added up and then rounded once to how the
    /// cable is sold. Parts: one per placed fixture, by Elektramat code; parts without a price
    /// cannot be ordered and are left out.
    static func lines(projects: [Project], cables: [Cable], fixtures: [Fixture], reserve: Double) -> [BillLine] {
        let cablesById = Dictionary(cables.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fixturesById = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [String] = []
        var lines: [String: BillLine] = [:]
        var required: [String: Double] = [:]

        func add(_ line: BillLine, room: String) {
            if var existing = lines[line.id] {
                existing.quantity += line.quantity
                if !existing.rooms.contains(room) { existing.rooms.append(room) }
                lines[line.id] = existing
            } else {
                order.append(line.id)
                lines[line.id] = line
            }
        }

        for project in projects {
            for run in project.cableRuns {
                guard let cable = cablesById[run.cableId], run.length > 0 else { continue }
                required[cable.id, default: 0] += PricingCalculator.requiredLength(measured: run.length, reserve: reserve)
                add(BillLine(kind: .cable, productId: cable.id, sku: cable.sku, name: cable.name,
                             detail: cable.crossSection, unitPrice: cable.pricePerMeter, quantity: 0, pieces: [],
                             productUrl: cable.productUrl, isSample: cable.isSample, rooms: [project.name]),
                    room: project.name)
            }
            for placement in project.placements {
                guard let fixture = fixturesById[placement.fixtureId] else { continue }
                for part in fixture.parts {
                    guard let price = part.price, price >= 0 else { continue }
                    add(BillLine(kind: .part, productId: part.sku, sku: part.sku, name: part.description,
                                 detail: "\(fixture.brand) \(fixture.line) · \(fixture.colourName)", unitPrice: price,
                                 quantity: 1, pieces: [], productUrl: part.productUrl, isSample: false,
                                 rooms: [project.name]),
                        room: project.name)
                }
            }
        }

        for (cableId, length) in required {
            guard let cable = cablesById[cableId], var line = lines["cable:\(cableId)"] else { continue }
            line.pieces = PricingCalculator.billedPieces(required: length, sales: cable.sales)
            line.quantity = line.pieces.reduce(0, +)
            lines[line.id] = line
        }
        return order.compactMap { lines[$0] }
    }

    static func total(_ lines: [BillLine]) -> Double {
        PricingCalculator.roundToCents(lines.reduce(0) { $0 + $1.linePrice })
    }

    /// Placed fixtures of which not every part can be ordered on elektramat.nl.
    static func incompleteFixtures(projects: [Project], fixtures: [Fixture]) -> Int {
        let complete = Dictionary(fixtures.map { ($0.id, $0.complete) }, uniquingKeysWith: { a, _ in a })
        return projects.flatMap(\.placements).filter { complete[$0.fixtureId] == false }.count
    }
}

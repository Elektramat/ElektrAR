import Combine
import Foundation

/// One cart line: meters of a cable, or a number of pieces of a switch or socket part
/// (identified by its Elektramat code).
nonisolated struct CartItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case cable
        case part
    }

    let id: UUID
    let kind: Kind
    /// Cable id for a cable, Elektramat code (sku) for a part.
    let productId: String
    let sku: String
    let name: String
    /// Cross-section for a cable, e.g. "Busch-Jaeger future linear · studiowit" for a part.
    let detail: String
    /// Price per meter (cable) or per piece (part), incl. VAT.
    let unitPrice: Double
    /// Meters (cable) or pieces (part).
    var quantity: Double
    let productUrl: URL
    let isSample: Bool

    var linePrice: Double { PricingCalculator.roundToCents(quantity * unitPrice) }
}

/// Reads the current format and the first one (cable only: cableId, crossSection,
/// pricePerMeter, meters), so carts saved by an older build still open.
nonisolated extension CartItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, productId, sku, name, detail, unitPrice, quantity, productUrl, isSample
        case cableId, crossSection, pricePerMeter, meters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .cable
        productId = try c.decodeIfPresent(String.self, forKey: .productId) ?? c.decode(String.self, forKey: .cableId)
        sku = try c.decode(String.self, forKey: .sku)
        name = try c.decode(String.self, forKey: .name)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
            ?? c.decodeIfPresent(String.self, forKey: .crossSection) ?? ""
        unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice) ?? c.decode(Double.self, forKey: .pricePerMeter)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? c.decode(Double.self, forKey: .meters)
        productUrl = try c.decode(URL.self, forKey: .productUrl)
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(productId, forKey: .productId)
        try c.encode(sku, forKey: .sku)
        try c.encode(name, forKey: .name)
        try c.encode(detail, forKey: .detail)
        try c.encode(unitPrice, forKey: .unitPrice)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(productUrl, forKey: .productUrl)
        try c.encode(isSample, forKey: .isSample)
    }
}

/// What happened when fixtures were added to the cart.
nonisolated struct FixtureCartResult: Equatable, Sendable {
    /// Pieces added, summed over all parts.
    var pieces = 0
    /// Fixtures of which not every part can be ordered on elektramat.nl.
    var incompleteFixtures = 0
}

/// In-app cart, persisted in UserDefaults.
@MainActor
final class CartStore: ObservableObject {
    @Published private(set) var items: [CartItem] = []

    private let defaults: UserDefaults
    private let key = "cart.items.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([CartItem].self, from: data) {
            items = saved
        }
    }

    var total: Double { PricingCalculator.roundToCents(items.reduce(0) { $0 + $1.linePrice }) }
    var count: Int { items.count }

    /// Adds meters of a cable. The same cable twice becomes one line with the meters added up.
    func add(cable: Cable, meters: Double) {
        guard meters.isFinite, meters > 0 else { return }
        add(CartItem(id: UUID(), kind: .cable, productId: cable.id, sku: cable.sku, name: cable.name,
                     detail: cable.crossSection, unitPrice: cable.pricePerMeter, quantity: meters,
                     productUrl: cable.productUrl, isSample: cable.isSample))
        save()
    }

    /// Adds `count` of a switch or socket as its separate parts (frame, rocker, insert, ...),
    /// each by its Elektramat code. The same code from different fixtures becomes one line.
    /// Parts without a price cannot be ordered and are skipped.
    @discardableResult
    func add(fixture: Fixture, count: Int) -> FixtureCartResult {
        var result = FixtureCartResult()
        guard count > 0 else { return result }
        if !fixture.complete { result.incompleteFixtures = count }
        for part in fixture.parts {
            guard let price = part.price, price >= 0 else { continue }
            add(CartItem(id: UUID(), kind: .part, productId: part.sku, sku: part.sku, name: part.description,
                         detail: "\(fixture.brand) \(fixture.line) · \(fixture.colourName)", unitPrice: price,
                         quantity: Double(count), productUrl: part.productUrl, isSample: false))
            result.pieces += count
        }
        save()
        return result
    }

    /// Sets the number of pieces of a part; 0 removes the line. Cables keep their measured length.
    func setQuantity(_ quantity: Int, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .part else { return }
        if quantity <= 0 {
            items.remove(at: index)
        } else {
            items[index].quantity = Double(quantity)
        }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        items = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    func removeAll() {
        items.removeAll()
        save()
    }

    private func add(_ item: CartItem) {
        if let index = items.firstIndex(where: { $0.kind == item.kind && $0.productId == item.productId }) {
            items[index].quantity += item.quantity
        } else {
            items.append(item)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

enum CartError: Error {
    case remoteCartNotAvailable
}

@MainActor
protocol CartService {
    func add(cable: Cable, meters: Double) throws
}

/// The cart the demo uses: lives in the app.
@MainActor
struct LocalCartService: CartService {
    let store: CartStore
    func add(cable: Cable, meters: Double) throws {
        store.add(cable: cable, meters: meters)
    }
}

/// TODO(open question): real webshop cart. The shop probably runs on Magento (unconfirmed).
/// Before building this, ask e-commerce/dev:
/// 1. How is cable sold: per meter, per roll, or cut to length?
/// 2. Are decimal quantities allowed?
/// 3. Is there a cart API that is reachable from outside?
/// 4. How would the app link a cart to the customer's browser session or account?
///
/// Tried on 19 Nov 2026: the Elektramat MCP server (https://mcp.elektramat.nl/mcp, no login)
/// has `cable_create_order(productId, amount, presetId)`, but without a login it returns only
/// "https://www.elektramat.nl/checkout/cart" with no cart id, token or cookie, so the browser
/// sees an empty cart. With an OAuth login it may land in the customer's own cart, but the
/// server only accepts redirect URIs of known assistants and localhost; an iOS app needs
/// Elektramat to allow its redirect. Ask the MCP team for that, or for a cart deep link.
@MainActor
struct RemoteCartService: CartService {
    func add(cable: Cable, meters: Double) throws {
        throw CartError.remoteCartNotAvailable
    }
}

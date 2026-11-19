import Combine
import Foundation

nonisolated struct CartItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let cableId: String
    let sku: String
    let name: String
    let crossSection: String
    let pricePerMeter: Double
    var meters: Double
    let productUrl: URL
    let isSample: Bool

    var linePrice: Double { PricingCalculator.roundToCents(meters * pricePerMeter) }
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
        if let index = items.firstIndex(where: { $0.cableId == cable.id }) {
            items[index].meters += meters
        } else {
            items.append(CartItem(id: UUID(), cableId: cable.id, sku: cable.sku, name: cable.name,
                                  crossSection: cable.crossSection, pricePerMeter: cable.pricePerMeter,
                                  meters: meters, productUrl: cable.productUrl, isSample: cable.isSample))
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

/// TODO(open question): a cart API with a hand-off to the customer's browser session or account.
/// What we know (19 Nov 2026, from elektramat.nl): the shop runs on Magento with Hyvä; cable is
/// sold per whole meter (minimum 1, no decimals) and as rolls and reels, which are separate
/// products. For the demo, `WebShopCart` posts the product form inside an in-app web view.
/// Still to ask e-commerce/dev: is there a cart API reachable from outside, and how would the
/// app link a cart to the customer's Safari session or account (for example a deep link)?
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

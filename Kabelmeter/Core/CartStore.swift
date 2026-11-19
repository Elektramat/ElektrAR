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

/// TODO(open question): real webshop cart. The shop probably runs on Magento (unconfirmed).
/// Before building this, ask e-commerce/dev:
/// 1. How is cable sold: per meter, per roll, or cut to length?
/// 2. Are decimal quantities allowed?
/// 3. Is there a cart API that is reachable from outside?
/// 4. How would the app link a cart to the customer's browser session or account?
@MainActor
struct RemoteCartService: CartService {
    func add(cable: Cable, meters: Double) throws {
        throw CartError.remoteCartNotAvailable
    }
}

import Foundation

/// One cart line as the elektramat.nl product form expects it.
nonisolated struct WebShopLine: Equatable, Sendable {
    let sku: String
    let name: String
    let productUrl: URL
    /// The shop sells cable per whole meter, so the quantity is a whole number of meters.
    let quantity: Int
}

nonisolated enum WebShopOrder {
    /// Whole meters to order. The cart already holds the billed length; the tolerance keeps
    /// 10.000000001 m at 10. Lines below 1 m or with an invalid length are skipped.
    static func lines(for items: [CartItem]) -> [WebShopLine] {
        items.compactMap { item in
            guard item.meters.isFinite, item.meters > 0 else { return nil }
            let quantity = Int((item.meters - 1e-6).rounded(.up))
            guard quantity >= 1 else { return nil }
            return WebShopLine(sku: item.sku, name: item.name, productUrl: item.productUrl, quantity: quantity)
        }
    }
}

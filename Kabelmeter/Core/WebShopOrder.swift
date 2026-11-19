import Foundation

/// One cart line as the elektramat.nl product form expects it.
nonisolated struct WebShopLine: Equatable, Sendable {
    let sku: String
    let name: String
    let productUrl: URL
    /// The shop's internal product id; nil means the app reads it from the product page first.
    let productId: Int?
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
            return WebShopLine(sku: item.sku, name: item.name, productUrl: item.productUrl,
                                productId: item.shopProductId, quantity: quantity)
        }
    }
}

nonisolated extension WebShopOrder {
    struct Shortfall: Equatable, Sendable {
        let line: WebShopLine
        /// Meters that did arrive in the shop cart for this line.
        let arrived: Int
    }

    /// Lines whose meters did not all arrive, comparing the shop cart (quantity per SKU) before
    /// and after posting. Lines with the same SKU share what arrived, in order.
    static func missing(_ lines: [WebShopLine], before: [String: Int], after: [String: Int]) -> [Shortfall] {
        var arrivedPerSku: [String: Int] = [:]
        for sku in Set(lines.map(\.sku)) {
            arrivedPerSku[sku] = max(0, (after[sku] ?? 0) - (before[sku] ?? 0))
        }
        var shortfalls: [Shortfall] = []
        for line in lines {
            let arrived = min(arrivedPerSku[line.sku] ?? 0, line.quantity)
            arrivedPerSku[line.sku, default: 0] -= arrived
            if arrived < line.quantity { shortfalls.append(Shortfall(line: line, arrived: arrived)) }
        }
        return shortfalls
    }
}

import Foundation

/// One elektramat.nl product that is part of a fixture (frame, rocker, socket insert, ...).
nonisolated struct FixturePart: Codable, Equatable, Sendable {
    let role: String
    let sku: String
    let description: String
    let price: Double?
    let productUrl: URL
    /// The shop's internal product id (lights only), so the cart can post it without loading the page.
    var shopProductId: Int? = nil
}

/// A smart-home light that mounts on a wall or ceiling, from Resources/lights.json
/// (made by scripts/scrape_lighting.py). There is no 3D model of the real product: the app
/// shows a stand-in shape of about the right size.
nonisolated struct LightProduct: Codable, Equatable, Sendable {
    let id: String
    let sku: String
    let name: String
    let brand: String
    /// "wall" or "ceiling".
    let surface: String
    /// "box", "cylinder", "disc", "recessed" or "surface".
    let shape: String
    /// Width, height and depth of the stand-in in mm.
    let sizeMM: [Double]
    /// Price incl. VAT.
    let price: Double
    let productUrl: URL
    let shopProductId: Int
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
    /// Lights only: the stand-in shape ("box", "cylinder", "disc", "recessed", "surface").
    var shape: String? = nil

    var isLight: Bool { product == "lamp" }

    /// Lights that hang on a ceiling go on a horizontal surface above the user.
    var isCeiling: Bool { mounting == "plafond" }

    var title: String {
        if isLight {
            switch shape {
            case "recessed": return "Inbouwspot"
            case "surface": return "Opbouwspot"
            case "disc": return "Plafondlamp"
            default: return "Wandlamp"
            }
        }
        let base = product == "stopcontact" ? "Stopcontact" : "Schakelaar"
        return mounting == "opbouw" ? "\(base) opbouw" : base
    }

    var colourName: String { colour.replacingOccurrences(of: "-", with: " ") }

    var subtitle: String { isLight ? productName : "\(brand) \(line) · \(colourName)" }

    /// The second line in the picker: the product name for a light, the colour for a switch.
    var detail: String { isLight ? productName : colourName }

    /// Name of the product photo in the bundle (LightImages/<sku>.jpg) for a light.
    var lightSku: String? { isLight ? parts.first?.sku : nil }
}

nonisolated extension Fixture {
    /// Fixture for a light: one part (the light itself), always orderable.
    init(light: LightProduct) {
        let size = light.sizeMM.count == 3 ? light.sizeMM : [100, 100, 50]
        id = "light-\(light.sku)"
        brand = light.brand
        line = light.surface == "ceiling" ? "Verlichting · plafond" : "Verlichting · wand"
        colour = ""
        product = "lamp"
        productName = light.name
        mounting = light.surface == "ceiling" ? "plafond" : "wand"
        model = "light-\(light.sku)"
        complete = true
        price = light.price
        parts = [FixturePart(role: "lamp", sku: light.sku, description: light.name, price: light.price,
                             productUrl: light.productUrl, shopProductId: light.shopProductId)]
        note = nil
        frameMM = [size[0], size[1]]
        depthMM = size[2]
        shape = light.shape
    }
}

nonisolated enum FixtureCatalog {
    static func decodeLights(_ data: Data) throws -> [Fixture] {
        try JSONDecoder().decode([LightProduct].self, from: data).map(Fixture.init(light:))
    }

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

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
/// (made by scripts/scrape_lighting.py). The 3D model (Models/light-<sku>.usdz, made by
/// scripts/generate_light_models.py) is indicative, not a CAD model of the real product.
nonisolated struct LightProduct: Codable, Equatable, Sendable {
    let id: String
    let sku: String
    let name: String
    let brand: String
    /// "wall" or "ceiling".
    let surface: String
    /// "box", "cylinder", "disc", "recessed" or "surface".
    let shape: String
    /// Width, height and depth of the light in mm (indicative).
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
    /// Lights only: the shape family ("box", "cylinder", "disc", "recessed", "surface"). Picks
    /// the generated model's design and the stand-in when the model file is missing.
    var shape: String? = nil

    var isLight: Bool { product == "lamp" }

    /// The standard consumer unit (groepenkast): a generic stand-in that is placed as the start
    /// of the cables. It is not a shop article and never goes into the cart.
    var isConsumerUnit: Bool { product == "groepenkast" }

    /// Lights that hang on a ceiling go on a horizontal surface above the user.
    var isCeiling: Bool { mounting == "plafond" }

    var title: String {
        if isConsumerUnit { return "Groepenkast" }
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

    var subtitle: String {
        if isConsumerUnit { return "Standaard weergave" }
        return isLight ? productName : "\(brand) \(line) · \(colourName)"
    }

    /// The second line in the picker: the product name for a light, the colour for a switch.
    var detail: String { isConsumerUnit ? "Niet te bestellen" : isLight ? productName : colourName }

    /// Name of the product photo in the bundle (LightImages/<sku>.jpg) for a light.
    var lightSku: String? { isLight ? parts.first?.sku : nil }
}

nonisolated extension Fixture {
    /// The generic consumer unit. A real one is configured with the configurator on elektramat.nl
    /// (https://www.elektramat.nl/groepenkasten/), so this has no parts and no price.
    static let consumerUnit = Fixture(
        id: "groepenkast", brand: "Standaard", line: "Standaard", colour: "", product: "groepenkast",
        productName: "Standaard groepenkast", mounting: "opbouw", model: "groepenkast", complete: true, price: nil,
        parts: [], note: "Alleen ter oriëntatie: de echte groepenkast stel je samen met de configurator op elektramat.nl.",
        frameMM: [220, 360], depthMM: 100, shape: "consumerunit")

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

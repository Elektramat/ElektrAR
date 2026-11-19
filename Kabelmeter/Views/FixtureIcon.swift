import SwiftUI

/// Rendered preview of the 3D model (FixtureImages/<model>.png, made by
/// scripts/render_fixture_previews.py), for lights too. Falls back to the product photo of a
/// light, then to a symbol.
struct FixtureIcon: View {
    let fixture: Fixture
    var size: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2)
            .fill(Theme.previewBackground)
            .frame(width: size, height: size)
            .overlay {
                if let image = Self.preview(for: fixture) {
                    Image(uiImage: image).resizable().scaledToFit().padding(size * 0.04)
                } else {
                    Image(systemName: fixture.isConsumerUnit ? "bolt.square"
                          : fixture.isLight ? "lightbulb"
                          : fixture.product == "stopcontact" ? "poweroutlet.type.f" : "lightswitch.on")
                        .font(size > 40 ? .title3 : .body)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
    }

    private static func preview(for fixture: Fixture) -> UIImage? {
        if let path = Bundle.main.path(forResource: fixture.model, ofType: "png")
            ?? Bundle.main.path(forResource: fixture.model, ofType: "png", inDirectory: "FixtureImages") {
            return UIImage(contentsOfFile: path)
        }
        if let sku = fixture.lightSku,
           let path = Bundle.main.path(forResource: sku, ofType: "jpg")
            ?? Bundle.main.path(forResource: sku, ofType: "jpg", inDirectory: "LightImages") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }
}

enum FixtureText {
    static func price(_ fixture: Fixture) -> String {
        if fixture.isConsumerUnit { return "Geen artikel" }
        if let price = fixture.price { return fixture.isLight ? Format.euro(price) : "\(Format.euro(price)) complete set" }
        return "Niet compleet te bestellen"
    }
}

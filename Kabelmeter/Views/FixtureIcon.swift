import SwiftUI

/// Rendered preview of the 3D model (FixtureImages/<model>.png, made by
/// scripts/render_fixture_previews.py), or a symbol when there is none.
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
                    Image(systemName: fixture.product == "stopcontact" ? "poweroutlet.type.f" : "lightswitch.on")
                        .font(size > 40 ? .title3 : .body)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
    }

    private static func preview(for fixture: Fixture) -> UIImage? {
        guard let path = Bundle.main.path(forResource: fixture.model, ofType: "png")
            ?? Bundle.main.path(forResource: fixture.model, ofType: "png", inDirectory: "FixtureImages") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

enum FixtureText {
    static func price(_ fixture: Fixture) -> String {
        if let price = fixture.price { return "\(Format.euro(price)) complete set" }
        return "Niet compleet te bestellen"
    }
}

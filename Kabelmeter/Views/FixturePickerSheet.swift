import SwiftUI

/// Searchable list of switches, sockets and lights, grouped by design line or light type.
struct FixturePickerSheet: View {
    let fixtures: [Fixture]
    @Binding var selectedId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Fixture] {
        guard !query.isEmpty else { return fixtures }
        return fixtures.filter {
            $0.subtitle.localizedCaseInsensitiveContains(query)
                || $0.title.localizedCaseInsensitiveContains(query)
                || $0.productName.localizedCaseInsensitiveContains(query)
        }
    }

    private var lines: [String] {
        var seen = Set<String>()
        return filtered.map(\.line).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(lines, id: \.self) { line in
                    Section(line) {
                        ForEach(filtered.filter { $0.line == line }) { fixture in
                            Button {
                                selectedId = fixture.id
                                dismiss()
                            } label: {
                                FixtureRow(fixture: fixture, selected: fixture.id == selectedId)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "Zoek serie, kleur, lamp of type")
            .sensoryFeedback(.selection, trigger: selectedId)
            .navigationTitle("Kies schakelaar of lamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
            }
        }
    }
}

private struct FixtureRow: View {
    let fixture: Fixture
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.spacing) {
            FixtureIcon(fixture: fixture)
            VStack(alignment: .leading, spacing: 2) {
                Text(fixture.title).font(.headline)
                Text(fixture.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(FixtureText.price(fixture)).font(.subheadline)
                    .foregroundStyle(fixture.complete ? .primary : Theme.warning)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

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
                    Image(systemName: fixture.isLight ? "lightbulb"
                          : fixture.product == "stopcontact" ? "poweroutlet.type.f" : "lightswitch.on")
                        .font(size > 40 ? .title3 : .body)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
    }

    private static func preview(for fixture: Fixture) -> UIImage? {
        if let sku = fixture.lightSku {
            guard let path = Bundle.main.path(forResource: sku, ofType: "jpg")
                ?? Bundle.main.path(forResource: sku, ofType: "jpg", inDirectory: "LightImages") else { return nil }
            return UIImage(contentsOfFile: path)
        }
        guard let path = Bundle.main.path(forResource: fixture.model, ofType: "png")
            ?? Bundle.main.path(forResource: fixture.model, ofType: "png", inDirectory: "FixtureImages") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

enum FixtureText {
    static func price(_ fixture: Fixture) -> String {
        if let price = fixture.price { return fixture.isLight ? Format.euro(price) : "\(Format.euro(price)) complete set" }
        return "Niet compleet te bestellen"
    }
}

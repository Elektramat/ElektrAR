import SwiftUI

/// Opens from "Wijzig" in the parts step (and from "Wissel" in the info card):
/// first a switch, socket or light, then the options grouped by brand.
struct FixtureChooserSheet: View {
    let fixtures: [Fixture]
    /// The last chosen fixture, offered as a shortcut ("Nog een").
    let recent: Fixture?
    let title: String
    let onChoose: (Fixture) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let kinds: [(product: String, title: String, icon: String)] = [
        ("schakelaar", "Schakelaar", "lightswitch.on"),
        ("stopcontact", "Stopcontact", "poweroutlet.type.f"),
        ("lamp", "Lamp", "lightbulb"),
    ]

    var body: some View {
        NavigationStack {
            List {
                if let recent {
                    Section("Nog een") {
                        Button { choose(recent) } label: {
                            HStack(spacing: Theme.spacing) {
                                FixtureIcon(fixture: recent, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recent.title).font(.headline)
                                    Text(recent.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Wat wil je plaatsen?") {
                    ForEach(Self.kinds, id: \.product) { kind in
                        let count = fixtures.filter { $0.product == kind.product }.count
                        NavigationLink(value: kind.product) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title).font(.title3.weight(.semibold))
                                    Text("\(count) uitvoeringen").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: kind.icon).font(.title2).foregroundStyle(Theme.accent)
                            }
                            .frame(minHeight: Theme.tapTarget)
                        }
                        .disabled(count == 0)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { product in
                FixtureBrandList(fixtures: fixtures.filter { $0.product == product },
                                 title: Self.kinds.first { $0.product == product }?.title ?? "Kies",
                                 selectedId: recent?.id, onChoose: choose)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
        }
    }

    private func choose(_ fixture: Fixture) {
        onChoose(fixture)
        dismiss()
    }
}

/// The options of one kind, one section per brand, sorted by design line and colour.
private struct FixtureBrandList: View {
    let fixtures: [Fixture]
    let title: String
    let selectedId: String?
    let onChoose: (Fixture) -> Void
    @State private var query = ""

    private var filtered: [Fixture] {
        let sorted = fixtures.sorted { ($0.brand, $0.line, $0.colour, $0.mounting) < ($1.brand, $1.line, $1.colour, $1.mounting) }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            "\($0.brand) \($0.line) \($0.colourName) \($0.mounting) \($0.productName)"
                .localizedCaseInsensitiveContains(query)
        }
    }

    private var brands: [String] {
        var seen = Set<String>()
        return filtered.map(\.brand).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            ForEach(brands, id: \.self) { brand in
                Section(brand) {
                    ForEach(filtered.filter { $0.brand == brand }) { fixture in
                        Button { onChoose(fixture) } label: {
                            HStack(spacing: Theme.spacing) {
                                FixtureIcon(fixture: fixture)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fixture.isLight ? fixture.productName : fixture.line).font(.headline).lineLimit(2)
                                    Text(fixture.isLight ? "\(fixture.title) · \(fixture.isCeiling ? "plafond" : "wand")"
                                         : fixture.mounting == "opbouw" ? "\(fixture.colourName) · opbouw" : fixture.colourName)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(FixtureText.price(fixture)).font(.subheadline)
                                        .foregroundStyle(fixture.complete ? .primary : Theme.warning)
                                }
                                Spacer()
                                if fixture.id == selectedId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "Zoek serie, kleur of lamp")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

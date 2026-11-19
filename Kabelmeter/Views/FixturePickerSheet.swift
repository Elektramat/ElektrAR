import SwiftUI

/// Searchable list of switches and sockets, grouped by design line.
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
            .searchable(text: $query, prompt: "Zoek serie, kleur of type")
            .navigationTitle("Kies schakelmateriaal")
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
                Text(fixture.colourName).font(.subheadline).foregroundStyle(.secondary)
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

struct FixtureIcon: View {
    let fixture: Fixture

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: fixture.product == "stopcontact" ? "poweroutlet.type.f" : "lightswitch.on")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}

enum FixtureText {
    static func price(_ fixture: Fixture) -> String {
        if let price = fixture.price { return "\(Format.euro(price)) complete set" }
        return "Niet compleet te bestellen"
    }
}

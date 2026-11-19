import SwiftUI

/// Pop-up after tapping a part or a cable: what it is, its size or height, and its price.
/// In the edit mode it also offers to remove, swap or move it.
struct InfoCard: View {
    let target: TapTarget
    @ObservedObject var placement: PlacementSession
    @ObservedObject var session: MeasureSession
    let isEditing: Bool
    let reserve: Double
    let onDelete: () -> Void
    let onReplace: () -> Void
    let onMove: () -> Void
    let onEdit: () -> Void

    @EnvironmentObject private var fixtureStore: FixtureStore
    @EnvironmentObject private var cableStore: CableStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                switch target {
                case let .fixture(id):
                    if let item = placement.placed.first(where: { $0.id == id }) {
                        fixtureInfo(item)
                    } else {
                        gone
                    }
                case let .cable(id):
                    if let run = session.runs.first(where: { $0.id == id }) {
                        cableInfo(run)
                    } else {
                        gone
                    }
                }
                actions
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var gone: some View {
        Text("Dit onderdeel is er niet meer.").foregroundStyle(.secondary)
    }

    // MARK: Part

    @ViewBuilder
    private func fixtureInfo(_ item: PlacedFixture) -> some View {
        let fixture = fixtureStore.fixture(id: item.fixtureId)
        Section {
            HStack(spacing: Theme.spacing) {
                if let fixture { FixtureIcon(fixture: fixture, size: 72) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(fixture?.title ?? "Onbekend onderdeel").font(.title3.bold())
                    if let fixture {
                        Text(fixture.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        if !fixture.isLight {
                            Text(fixture.productName).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text(fixture.isCeiling ? "Plafond" : "Wand").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let height = FloorHeight.height(of: item.position, floorY: session.floorY) {
                row("Hoogte (midden)", "\(Format.height(height)) boven de vloer")
            }
            if let fixture {
                row("Prijs", fixture.price.map(Format.euro) ?? "Niet compleet te bestellen",
                    warning: !fixture.complete)
                if placement.cabled.contains(item.id) {
                    row("Kabel", "Automatisch aangesloten")
                }
            }
        }
        if let fixture, !fixture.parts.isEmpty {
            Section {
                ForEach(fixture.parts, id: \.sku) { part in
                    Button { openURL(part.productUrl) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.description).foregroundStyle(.primary)
                                Text("art.nr. \(part.sku) · \(part.role)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(part.price.map(Format.euro) ?? "–").monospacedDigit().foregroundStyle(.primary)
                            Image(systemName: "safari").foregroundStyle(Theme.accent)
                        }
                    }
                }
            } header: {
                Text("Onderdelen")
            } footer: {
                if let note = fixture.note, !fixture.complete { Text(note) }
            }
        }
    }

    // MARK: Cable

    @ViewBuilder
    private func cableInfo(_ run: CableRun) -> some View {
        let cable = cableStore.cables.first { $0.id == run.cableId }
        let quote = cable.flatMap { PricingCalculator.quote(for: $0, measured: run.length, reserve: reserve) }
        Section {
            HStack(spacing: Theme.spacing) {
                Image(systemName: "cable.connector").font(.largeTitle).foregroundStyle(Theme.run)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cable?.name ?? "Kabel").font(.title3.bold())
                    if let cable { Text("\(cable.crossSection) · \(cable.use)").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            row("Lengte", Format.meters(run.length))
            row("Ankerpunten", "\(run.points.count)")
            if let quote {
                row("Nodig met reserve", Format.meters(quote.required))
                row("Te bestellen", Format.pieces(quote.pieces))
                row("Prijs", Format.euro(quote.price))
            }
            if let cable {
                Button { openURL(cable.productUrl) } label: {
                    Label("Bekijk op elektramat.nl", systemImage: "safari")
                }
            }
        } footer: {
            Text("Prijs voor deze kabel apart. In de winkelwagen worden alle kabels van hetzelfde type samen afgerond, dat is vaak iets voordeliger.")
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        Section {
            if isEditing {
                if case .fixture = target {
                    Button(action: onReplace) { Label("Wissel voor een ander onderdeel", systemImage: "arrow.triangle.2.circlepath") }
                    Button(action: onMove) { Label("Verplaats", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                }
                Button(role: .destructive, action: onDelete) { Label("Verwijder", systemImage: "trash") }
            } else {
                Button(action: onEdit) { Label("Bewerk", systemImage: "pencil") }
            }
        }
    }

    private func row(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.semibold).foregroundStyle(warning ? Theme.warning : .primary)
        }
    }
}

import SwiftUI

/// The shared shopping list of all rooms, plus the button that opens it.
/// It is worked out from the rooms (see `Bill`), so it always matches the designs.
struct CartScreen: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var fixtureStore: FixtureStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)

    private var lines: [BillLine] {
        Bill.lines(projects: projectStore.projects, cables: cableStore.cables, fixtures: fixtureStore.fixtures,
                   reserve: Double(reservePercent) / 100)
    }

    var body: some View {
        let lines = lines
        let cables = lines.filter { $0.kind == .cable }
        let parts = lines.filter { $0.kind == .part }
        let incomplete = Bill.incompleteFixtures(projects: projectStore.projects, fixtures: fixtureStore.fixtures)

        NavigationStack {
            List {
                if lines.isEmpty {
                    ContentUnavailableView("Je winkelwagen is leeg", systemImage: "cart",
                                           description: Text("Alles wat je in je ruimtes plaatst en trekt, komt hier vanzelf bij elkaar."))
                } else {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Totaal").font(.headline)
                                Text("Uit \(projectStore.projects.filter { !$0.placements.isEmpty || !$0.runs.isEmpty }.count) ruimtes")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.euro(Bill.total(lines))).font(.title.bold()).monospacedDigit()
                        }
                        if incomplete > 0 {
                            Label("\(incomplete) schakelaars of stopcontacten zijn niet compleet te bestellen; de ontbrekende onderdelen staan er niet bij.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !cables.isEmpty {
                    Section {
                        ForEach(cables) { line in row(line) }
                        Stepper(value: $reservePercent, in: 0...30, step: 5) {
                            Text("Reserve \(reservePercent)% + \(Format.orderLength(PricingCalculator.connectionAllowance)) aansluiting per kabel")
                                .font(.footnote)
                        }
                    } header: {
                        Text("Kabel")
                    }
                }
                if !parts.isEmpty {
                    Section("Schakelmateriaal") {
                        ForEach(parts) { line in row(line) }
                    }
                }

                Section {
                    Text("Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Winkelwagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
        }
    }

    private func row(_ line: BillLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.name).font(.headline)
                Spacer()
                Text(Format.euro(line.linePrice)).font(.headline).monospacedDigit()
            }
            Group {
                switch line.kind {
                case .cable:
                    Text("\(line.detail) · \(Format.pieces(line.pieces)) × \(Format.euro(line.unitPrice)) per meter")
                case .part:
                    Text("\(Format.quantity(line.quantity)) × \(Format.euro(line.unitPrice)) · art.nr. \(line.sku)")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Label(line.rooms.joined(separator: ", "), systemImage: "square.split.bottomrightquarter")
                .font(.caption).foregroundStyle(.secondary)
            if line.isSample { SampleBadge() }
            Button { openURL(line.productUrl) } label: {
                Label("Bestel op elektramat.nl", systemImage: "safari")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

/// Always-visible cart button with the total of all rooms.
struct CartButton: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var fixtureStore: FixtureStore
    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)
    @State private var showCart = false

    var body: some View {
        let total = Bill.total(Bill.lines(projects: projectStore.projects, cables: cableStore.cables,
                                          fixtures: fixtureStore.fixtures, reserve: Double(reservePercent) / 100))
        Button { showCart = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "cart.fill")
                Text(Format.euro(total)).monospacedDigit().contentTransition(.numericText())
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Winkelwagen, \(Format.euro(total))")
        .sheet(isPresented: $showCart) { CartScreen() }
    }
}

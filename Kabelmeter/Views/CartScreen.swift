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
    @State private var webShopLines: [WebShopLine] = []
    @State private var showWebShop = false
    /// Created with the cart screen and warmed up right away, so adding to the shop is faster.
    @StateObject private var shop = WebShopCart()

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
                        // Sample cables have no real product page, so they stay out of the shop cart.
                        let realLines = WebShopOrder.lines(for: lines.filter { !$0.isSample })
                        Button {
                            webShopLines = realLines
                            showWebShop = true
                        } label: {
                            Label("Zet in winkelwagen op elektramat.nl", systemImage: "cart.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
                        }
                        .brandProminentButton(Theme.cta)
                        .buttonBorderShape(.roundedRectangle(radius: Theme.buttonCorner))
                        .disabled(realLines.isEmpty || showWebShop || shop.isBusy)
                        if lines.contains(where: \.isSample) {
                            Text("Voorbeeldkabels gaan niet mee naar de webshop.")
                                .font(.footnote).foregroundStyle(.secondary)
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
                        if cables.contains(where: { $0.rollLength != nil }) {
                            Text("Rollen gekozen op de laagste totaalprijs voor de lengte uit al je ruimtes samen.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
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
            .sheet(isPresented: $showWebShop) { WebShopSheet(lines: webShopLines, shop: shop) }
            .onAppear { if !lines.isEmpty { shop.warmUp() } }
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
                    if let rollLength = line.rollLength {
                        Text("\(line.detail) · \(line.rollCount) × \(Format.euro(PricingCalculator.roundToCents(line.unitPrice * rollLength))) per rol · art.nr. \(line.sku)")
                    } else {
                        Text("\(line.detail) · \(Format.pieces(line.pieces)) × \(Format.euro(line.unitPrice)) per meter")
                    }
                case .part:
                    Text("\(Format.quantity(line.quantity)) × \(Format.euro(line.unitPrice)) · art.nr. \(line.sku)")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Label(line.rooms.joined(separator: ", "), systemImage: "square.split.bottomrightquarter")
                .font(.caption).foregroundStyle(.secondary)
            if line.isSample { SampleBadge() }
            Button { openURL(line.productUrl) } label: {
                HStack(spacing: 6) {
                    Text("Bekijk op elektramat.nl")
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 40)
            }
            .buttonStyle(.borderless)
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
                Image(systemName: "cart.fill").foregroundStyle(Theme.accent)
                Text(Format.euro(total)).monospacedDigit().contentTransition(.numericText())
                    .animation(.snappy, value: total)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .surface(Capsule())
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel("Winkelwagen, \(Format.euro(total))")
        .sheet(isPresented: $showCart) { CartScreen() }
    }
}

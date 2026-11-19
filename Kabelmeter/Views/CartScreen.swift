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
                            Label {
                                Text("\(incomplete) schakelaars of stopcontacten zijn niet compleet te bestellen; de ontbrekende onderdelen staan er niet bij.")
                                    .foregroundStyle(Theme.inkSecondary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                            }
                            .font(.footnote)
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
                        HStack {
                            Text("Reserve \(reservePercent)% + \(Format.orderLength(PricingCalculator.connectionAllowance)) aansluiting per kabel")
                                .font(.footnote)
                            Spacer(minLength: 8)
                            BrandStepper(value: $reservePercent, range: 0...30, step: 5,
                                         accessibilityName: "Reserve in procent")
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
    /// Compact: a round cart icon with a green count badge, for the crowded camera bar.
    /// Otherwise the icon with the total price, which never wraps.
    var compact = false
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var fixtureStore: FixtureStore
    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)
    @State private var showCart = false

    var body: some View {
        let lines = Bill.lines(projects: projectStore.projects, cables: cableStore.cables,
                               fixtures: fixtureStore.fixtures, reserve: Double(reservePercent) / 100)
        let total = Bill.total(lines)
        Button { showCart = true } label: {
            if compact {
                Image(systemName: "cart.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .surface(Circle())
                    .overlay(alignment: .topTrailing) {
                        if !lines.isEmpty {
                            Text("\(lines.count)")
                                .font(.caption2.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Theme.cta, in: Capsule())
                                .offset(x: 4, y: -4)
                        }
                    }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "cart.fill").foregroundStyle(Theme.accent)
                    Text(Format.euro(total)).monospacedDigit().contentTransition(.numericText())
                        .animation(.snappy, value: total)
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .surface(Capsule())
            }
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel("Winkelwagen, \(lines.count) artikelen, \(Format.euro(total))")
        .sheet(isPresented: $showCart) { CartScreen() }
    }
}

import SwiftUI

struct CartScreen: View {
    @EnvironmentObject private var cart: CartStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var webShopLines: [WebShopLine] = []
    @State private var showWebShop = false

    /// Sample cables have no real product page, so they stay out of the shop cart.
    private var realLines: [WebShopLine] { WebShopOrder.lines(for: cart.items.filter { !$0.isSample }) }

    var body: some View {
        NavigationStack {
            List {
                if cart.items.isEmpty {
                    ContentUnavailableView("Je winkelmand is leeg", systemImage: "cart",
                                           description: Text("Meet een route en voeg de kabel toe."))
                } else {
                    Section {
                        ForEach(cart.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.name).font(.headline)
                                    Spacer()
                                    Text(Format.euro(item.linePrice)).font(.headline).monospacedDigit()
                                }
                                Text("\(item.crossSection) · \(Format.orderLength(item.meters)) × \(Format.euro(item.pricePerMeter)) per meter")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if item.isSample { SampleBadge() }
                                Button {
                                    openURL(item.productUrl)
                                } label: {
                                    Label("Bekijk op elektramat.nl", systemImage: "safari")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { cart.remove(atOffsets: $0) }
                    }

                    Section {
                        HStack {
                            Text("Totaal").font(.headline)
                            Spacer()
                            Text(Format.euro(cart.total)).font(.title2.bold()).monospacedDigit()
                        }
                        Button {
                            webShopLines = realLines
                            showWebShop = true
                        } label: {
                            Label("Zet in winkelmand op elektramat.nl", systemImage: "cart.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(realLines.isEmpty || showWebShop)
                        if cart.items.contains(where: \.isSample) {
                            Text("Voorbeeldkabels gaan niet mee naar de webshop.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showWebShop) { WebShopSheet(lines: webShopLines) }
            .navigationTitle("Winkelmand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
                if !cart.items.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Leegmaken", role: .destructive) { cart.removeAll() }
                    }
                }
            }
        }
    }
}

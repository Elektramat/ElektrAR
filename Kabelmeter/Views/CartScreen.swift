import SwiftUI

struct CartScreen: View {
    @EnvironmentObject private var cart: CartStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var webShopLines: [WebShopLine] = []
    @State private var showWebShop = false
    /// Created with the cart screen and warmed up right away, so adding to the shop is faster.
    @StateObject private var shop = WebShopCart()

    /// Sample cables have no real product page, so they stay out of the shop cart.
    private var realLines: [WebShopLine] { WebShopOrder.lines(for: cart.items.filter { !$0.isSample }) }

    var body: some View {
        NavigationStack {
            List {
                if cart.items.isEmpty {
                    ContentUnavailableView("Je winkelmand is leeg", systemImage: "cart",
                                           description: Text("Meet een kabel of plaats schakelaars en voeg ze toe."))
                } else {
                    Section {
                        ForEach(cart.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.name).font(.headline)
                                    Spacer()
                                    Text(Format.euro(item.linePrice)).font(.headline).monospacedDigit()
                                        .contentTransition(.numericText(value: item.linePrice))
                                        .animation(.snappy, value: item.linePrice)
                                }
                                switch item.kind {
                                case .cable:
                                    Text("\(item.detail) · \(Format.orderLength(item.quantity)) × \(Format.euro(item.unitPrice)) per meter")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                case .part:
                                    Text("\(item.detail) · art.nr. \(item.sku)")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Stepper(value: Binding(get: { Int(item.quantity) },
                                                           set: { cart.setQuantity($0, for: item.id) }),
                                            in: 1...99) {   // removing is the trash button
                                        Text("\(Format.quantity(item.quantity)) × \(Format.euro(item.unitPrice))")
                                            .monospacedDigit()
                                            .contentTransition(.numericText(value: item.quantity))
                                            .animation(.snappy, value: item.quantity)
                                    }
                                    .sensoryFeedback(.selection, trigger: item.quantity)
                                }
                                if item.isSample { SampleBadge() }
                                // A light text link with its own space, not a second filled button
                                // right under the stepper; the trash button removes the whole line.
                                HStack {
                                    Button {
                                        openURL(item.productUrl)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("Bekijk op elektramat.nl")
                                            Image(systemName: "arrow.up.right")
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                        .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    Spacer()
                                    Button {
                                        withAnimation { cart.remove(id: item.id) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(Theme.alert)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(CardButtonStyle())
                                    .accessibilityLabel("Verwijder \(item.name)")
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 8)
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
                        .brandProminentButton()
                        .disabled(realLines.isEmpty || showWebShop || shop.isBusy)
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
            .sheet(isPresented: $showWebShop) { WebShopSheet(lines: webShopLines, shop: shop) }
            .onAppear { if !realLines.isEmpty { shop.warmUp() } }
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

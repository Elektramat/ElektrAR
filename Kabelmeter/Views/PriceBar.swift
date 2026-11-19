import SwiftUI

/// Always visible at the bottom: measured length, length to order, price, reserve.
struct PriceBar: View {
    let cable: Cable?
    let measured: Double
    /// Live quote, including the preview segment to the crosshair.
    let quote: Quote?
    /// Quote of the confirmed points only; this is what goes into the cart.
    let cartQuote: Quote?
    @Binding var mode: RouteMode
    @Binding var reservePercent: Int
    let onAddToCart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gemeten: \(Format.meters(measured))")
                        .font(Theme.lengthFont)
                        .monospacedDigit()
                    Text(quote.map { "Te bestellen: \(Format.pieces($0.pieces))" } ?? "Te bestellen: –")
                        .font(Theme.lengthFont)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    if let quote {
                        Text(Format.euro(quote.price))
                            .font(Theme.priceFont)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } else if let cable {
                        Text(Format.euro(cable.pricePerMeter))
                            .font(Theme.priceFont)
                        Text("per meter").font(Theme.labelFont).foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Route", selection: $mode) {
                Text("Langs de muur").tag(RouteMode.alongWall)
                Text("Rechte lijn").tag(RouteMode.straight)
            }
            .pickerStyle(.segmented)

            Stepper(value: $reservePercent, in: 0...30, step: 5) {
                Text("Reserve \(reservePercent)% + \(Format.orderLength(PricingCalculator.connectionAllowance)) aansluiting")
                    .font(Theme.labelFont)
            }

            Button(action: onAddToCart) {
                Label(cartQuote.map { "Voeg \(Format.pieces($0.pieces)) toe aan winkelmand" }
                      ?? "Zet minstens 2 punten", systemImage: "cart.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cartQuote == nil || cable == nil)
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

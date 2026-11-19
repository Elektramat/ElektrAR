import SwiftUI

/// Always visible at the bottom: measured length, length to order, price, reserve.
struct PriceBar: View {
    let cable: Cable?
    let measured: Double
    let quote: Quote?
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

            Stepper(value: $reservePercent, in: 0...30, step: 5) {
                Text("Reserve \(reservePercent)% + \(Format.orderLength(PricingCalculator.connectionAllowance)) aansluiting")
                    .font(Theme.labelFont)
            }

            Button(action: onAddToCart) {
                Label("Voeg toe aan winkelmand", systemImage: "cart.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabled(quote == nil || cable == nil)
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

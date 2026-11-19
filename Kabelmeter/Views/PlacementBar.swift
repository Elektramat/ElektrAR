import SwiftUI

/// Bottom bar while placing switches: the selected fixture and what has been placed so far.
struct PlacementBar: View {
    let fixture: Fixture?
    let placedCount: Int
    let total: (price: Double, incomplete: Int)
    /// False in Demo-modus: simulated placements are not saved.
    let persists: Bool
    /// Placed fixtures that are not in the cart yet.
    let newCount: Int
    let onAddToCart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Geplaatst: \(placedCount)")
                        .font(Theme.lengthFont)
                        .monospacedDigit()
                    if let fixture {
                        Text("\(fixture.title) · \(FixtureText.price(fixture))")
                            .font(Theme.labelFont)
                            .foregroundStyle(fixture.complete ? .secondary : Theme.warning)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.euro(total.price))
                        .font(Theme.priceFont)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if total.incomplete > 0 {
                        Text("\(total.incomplete) zonder prijs").font(Theme.labelFont).foregroundStyle(Theme.warning)
                    }
                }
            }
            Button(action: onAddToCart) {
                Label(buttonTitle, systemImage: "cart.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .brandProminentButton()
            .disabled(newCount == 0)

            if persists {
                Text("Plaatsingen blijven bewaard en komen terug als je de app opnieuw opent in deze ruimte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.spacing)
        .surface(RoundedRectangle(cornerRadius: Theme.corner))
    }

    private var buttonTitle: String {
        if placedCount > 0, newCount == 0 { return "Alles in winkelmand" }
        return newCount > 1 ? "Voeg \(newCount) toe aan winkelmand" : "Voeg toe aan winkelmand"
    }
}

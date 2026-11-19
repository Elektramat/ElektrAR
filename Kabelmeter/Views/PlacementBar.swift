import SwiftUI

/// Bottom bar while placing switches: the selected fixture and what has been placed so far.
struct PlacementBar: View {
    let fixture: Fixture?
    let placedCount: Int
    let total: (price: Double, incomplete: Int)
    /// False in Demo-modus: simulated placements are not saved.
    let persists: Bool

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
            if persists {
                Text("Plaatsingen blijven bewaard en komen terug als je de app opnieuw opent in deze ruimte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

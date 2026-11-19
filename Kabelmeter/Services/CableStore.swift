import Combine
import Foundation

/// Loads cables.json from the app bundle.
@MainActor
final class CableStore: ObservableObject {
    @Published private(set) var cables: [Cable] = []
    @Published private(set) var loadError: String?

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "cables", withExtension: "json") else {
            loadError = "Kabellijst niet gevonden in de app."
            return
        }
        do {
            cables = try CableCatalog.decode(Data(contentsOf: url))
            if cables.isEmpty { loadError = "De kabellijst is leeg." }
        } catch {
            loadError = "Kabellijst kon niet worden gelezen."
        }
    }

    var hasSampleData: Bool { cables.contains(where: \.isSample) }
}

import Combine
import Foundation

/// Loads fixtures.json (switches and sockets with a 3D model) from the app bundle.
@MainActor
final class FixtureStore: ObservableObject {
    @Published private(set) var fixtures: [Fixture] = []
    @Published private(set) var loadError: String?

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "fixtures", withExtension: "json") else {
            loadError = "Lijst met schakelaars niet gevonden in de app."
            return
        }
        do {
            fixtures = try FixtureCatalog.decode(Data(contentsOf: url))
            if fixtures.isEmpty { loadError = "De lijst met schakelaars is leeg." }
        } catch {
            loadError = "Lijst met schakelaars kon niet worden gelezen."
        }
    }

    func fixture(id: String?) -> Fixture? {
        guard let id else { return nil }
        return fixtures.first { $0.id == id }
    }
}

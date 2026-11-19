import Combine
import Foundation

/// Loads fixtures.json (switches and sockets with a 3D model) and lights.json (wall and ceiling lights) from the app bundle.
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
            if let lights = bundle.url(forResource: "lights", withExtension: "json") {
                fixtures += try FixtureCatalog.decodeLights(Data(contentsOf: lights))
            }
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

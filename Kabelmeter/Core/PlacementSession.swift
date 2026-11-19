import Combine
import Foundation
import simd

/// Pose math for putting a model flat on a wall.
nonisolated enum WallPose {
    /// Surfaces whose normal points more than this far up or down are floors or ceilings.
    static let maxNormalY: Float = 0.7

    /// A transform at `position` with +Z pointing out of the wall towards the camera and
    /// +Y pointing up along the wall, so a switch hangs upright. This matches the models:
    /// their back sits at z = 0 and +Z points out of the wall. `offset` lifts the model
    /// off the wall a little to avoid z-fighting. Nil when the surface is not a wall.
    static func make(position: SIMD3<Float>, normal: SIMD3<Float>, cameraPosition: SIMD3<Float>,
                     offset: Float = 0.0005) -> simd_float4x4? {
        guard simd_length(normal) > 1e-6 else { return nil }
        var z = simd_normalize(normal)
        if simd_dot(z, cameraPosition - position) < 0 { z = -z }
        guard abs(z.y) <= maxNormalY else { return nil }
        let up = SIMD3<Float>(0, 1, 0)
        let y = simd_normalize(up - simd_dot(up, z) * z)
        let x = simd_cross(y, z)
        let p = position + z * offset
        return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(p, 1)))
    }
}

nonisolated struct PlacedFixture: Identifiable, Equatable, Sendable {
    let id: UUID
    let fixtureId: String
    /// World transform: +Z out of the wall, +Y up.
    let transform: simd_float4x4

    var position: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}

/// Switches and sockets placed on walls. The UI calls place/remove/replace/undo; a
/// MeasureProvider writes `cursor`, draws `placed` and keeps them fixed in the room.
@MainActor
final class PlacementSession: ObservableObject {
    @Published private(set) var placed: [PlacedFixture] = []
    /// Pose on the wall under the crosshair; nil when no wall is hit.
    @Published var cursor: simd_float4x4?
    /// True while placing parts: the provider aims at walls and shows a preview.
    @Published var isActive = false
    /// The fixture shown as a see-through preview at the crosshair.
    @Published var selectedFixtureId: String?
    /// Set when the preview is snapped to a cable point or next to another fixture.
    @Published var guide: MeasureGuide?
    /// What the preview lines up with (level, straight above, standard height).
    @Published var alignment = Alignment.none
    /// True while ARKit tries to recognise the saved room.
    @Published var isRestoring = false
    /// Placements that have an automatic cable, in routing order.
    @Published private(set) var cabled: [UUID] = []
    /// The placement whose info card is open; drawn highlighted.
    @Published var selectedId: UUID?
    /// A saved room to open. The provider picks it up, clears it and, in AR, first recognises the room.
    @Published var pendingLoad: ProjectLoad?
    /// Set once the room's content is back on screen; until then nothing may be saved over it.
    @Published var loadedRoomId: UUID?
    /// Fires when the room is not recognised and the user wants to see the design here anyway.
    let skipRestoreRequests = PassthroughSubject<Void, Never>()

    var canPlace: Bool { isActive && cursor != nil }

    /// Places at a pose taken earlier (the "+" first asks which fixture).
    func place(_ fixtureId: String, at pose: simd_float4x4) {
        placed.append(PlacedFixture(id: UUID(), fixtureId: fixtureId, transform: pose))
    }

    func remove(_ id: UUID) {
        placed.removeAll { $0.id == id }
        cabled.removeAll { $0 == id }
        if selectedId == id { selectedId = nil }
    }

    /// Swaps a placement for another fixture at the same spot; its cable stays.
    func replace(_ id: UUID, with fixtureId: String) {
        guard let index = placed.firstIndex(where: { $0.id == id }) else { return }
        let new = PlacedFixture(id: UUID(), fixtureId: fixtureId, transform: placed[index].transform)
        placed[index] = new
        cabled = cabled.map { $0 == id ? new.id : $0 }
        if selectedId == id { selectedId = new.id }
    }

    /// Placements without an automatic cable yet.
    var notCabled: [PlacedFixture] { placed.filter { !cabled.contains($0.id) } }

    func markCabled(_ ids: [UUID]) {
        cabled += ids.filter { !cabled.contains($0) }
    }

    /// Replaces everything with a saved room.
    func load(_ fixtures: [PlacedFixture], cabled: [UUID], roomId: UUID) {
        loadedRoomId = roomId
        placed = fixtures
        self.cabled = cabled.filter { id in fixtures.contains { $0.id == id } }
        selectedId = nil
    }

    func undo() {
        if let last = placed.last { remove(last.id) }
    }

    func clearAll() {
        placed.removeAll()
        cabled.removeAll()
        selectedId = nil
    }

    /// Connection points of every placed fixture plus the points of the given cables.
    func connectionPoints(catalog: [String: Fixture], cables: [[SIMD3<Float>]]) -> [ConnectionPoint] {
        let fixtures = placed.map { item in
            (transform: item.transform, size: FixtureGeometry.size(frameMM: catalog[item.fixtureId]?.frameMM))
        }
        return ConnectionSnapping.points(fixtures: fixtures, cables: cables)
    }
}

/// A saved room to open, with its AR room map to recognise first (nil when
/// the room map could not be saved).
nonisolated struct ProjectLoad: Sendable {
    let project: Project
    let mapURL: URL?
}

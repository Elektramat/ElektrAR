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

/// Pose math for putting a light flat on a ceiling.
nonisolated enum CeilingPose {
    /// Surfaces whose normal is less vertical than this are walls, not ceilings.
    static let minNormalY: Float = 0.7
    /// A ceiling must be at least this far above the camera, so a table or the floor is not one.
    static let minHeightAboveCamera: Float = 0.3

    /// A transform at `position` with +Z pointing down out of the ceiling and +Y along the
    /// horizontal direction the camera looks, so the light turns with the user. The models
    /// have their back at z = 0, like the wall models. Nil when the surface is not a ceiling
    /// above the camera.
    static func make(position: SIMD3<Float>, normal: SIMD3<Float>, cameraPosition: SIMD3<Float>,
                     cameraForward: SIMD3<Float>, offset: Float = 0.0005) -> simd_float4x4? {
        guard simd_length(normal) > 1e-6, abs(simd_normalize(normal).y) >= minNormalY,
              position.y - cameraPosition.y >= minHeightAboveCamera else { return nil }
        let z = SIMD3<Float>(0, -1, 0)
        var forward = SIMD3<Float>(cameraForward.x, 0, cameraForward.z)
        // Looking straight up: no horizontal direction, so face along -Z.
        forward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : SIMD3<Float>(0, 0, -1)
        let x = simd_cross(forward, z)
        let p = position + z * offset
        return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(forward, 0), SIMD4(z, 0), SIMD4(p, 1)))
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

/// Switches and sockets placed on walls. The UI calls place/undo/clearAll; a
/// MeasureProvider writes `cursor`, draws `placed` and keeps them in the world
/// (and, on a device, saves them with the room so they come back after a restart).
@MainActor
final class PlacementSession: ObservableObject {
    @Published private(set) var placed: [PlacedFixture] = []
    /// Pose on the wall under the crosshair; nil when no wall is hit.
    @Published var cursor: simd_float4x4?
    /// True while the "Plaatsen" mode is on.
    @Published var isActive = false
    /// The fixture the "+" button places; the provider shows it as a preview at the crosshair.
    @Published var selectedFixtureId: String?
    /// Set when the preview is snapped to a cable point or next to another fixture.
    @Published var guide: MeasureGuide?
    /// Placements that are already in the cart, so adding again only adds the new ones.
    @Published private(set) var inCart: Set<UUID> = []
    /// True while ARKit tries to recognise the room of the saved placements.
    @Published var isRestoring = false
    /// Fires when the user wants to start over in a different room.
    let newRoomRequests = PassthroughSubject<Void, Never>()

    var canPlace: Bool { isActive && cursor != nil }

    @discardableResult
    func place(_ fixtureId: String) -> Bool {
        guard canPlace, let cursor else { return false }
        placed.append(PlacedFixture(id: UUID(), fixtureId: fixtureId, transform: cursor))
        return true
    }

    /// Adds a placement that came back from a saved room. Ignores ids it already has.
    func restore(_ fixture: PlacedFixture) {
        guard !placed.contains(where: { $0.id == fixture.id }) else { return }
        placed.append(fixture)
    }

    func undo() {
        if let last = placed.popLast() { inCart.remove(last.id) }
    }

    func clearAll() {
        placed.removeAll()
        inCart.removeAll()
    }

    func startNewRoom() {
        placed.removeAll()
        inCart.removeAll()
        isRestoring = false
        newRoomRequests.send()
    }

    /// Placements not yet in the cart, counted per fixture id (in placing order).
    var notInCart: [(fixtureId: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for item in placed where !inCart.contains(item.id) {
            if counts[item.fixtureId] == nil { order.append(item.fixtureId) }
            counts[item.fixtureId, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    func markAllInCart() {
        inCart = Set(placed.map(\.id))
    }

    /// Connection points of every placed fixture plus the points of the given cables.
    func connectionPoints(catalog: [String: Fixture], cables: [[SIMD3<Float>]]) -> [ConnectionPoint] {
        let fixtures = placed.map { item in
            (transform: item.transform, size: FixtureGeometry.size(frameMM: catalog[item.fixtureId]?.frameMM))
        }
        return ConnectionSnapping.points(fixtures: fixtures, cables: cables)
    }

    /// Sum of the complete sets, and how many placed fixtures have no complete price.
    func total(in catalog: [Fixture]) -> (price: Double, incomplete: Int) {
        let byId = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var price = 0.0
        var incomplete = 0
        for item in placed {
            if let p = byId[item.fixtureId]?.price { price += p } else { incomplete += 1 }
        }
        return (PricingCalculator.roundToCents(price), incomplete)
    }
}

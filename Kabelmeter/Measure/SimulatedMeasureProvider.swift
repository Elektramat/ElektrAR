import Combine
import Foundation
import simd

/// Fake measuring for the Simulator. The crosshair walks along a
/// route on a wall (x = horizontal, y = height, in meters), so the length and price
/// change live, just like on a device.
@MainActor
final class SimulatedMeasureProvider: ObservableObject, MeasureProvider {
    /// Route from the electrical cabinet up, along the ceiling line, and down to a switch.
    static let route: [SIMD3<Float>] = [
        [0.0, 0.9, 0], [0.0, 2.3, 0], [3.2, 2.3, 0], [3.2, 1.05, 0], [4.6, 1.05, 0],
    ]
    private static let speed: Float = 0.35 // meters per second

    private weak var session: MeasureSession?
    private weak var placement: PlacementSession?
    private var timer: AnyCancellable?
    private var travelled: Float = 0
    /// Fixtures by id, for their frame sizes when snapping.
    var catalog: [String: Fixture] = [:]

    func start(session: MeasureSession, placement: PlacementSession) {
        self.session = session
        self.placement = placement
        session.trackingMessage = nil
        session.floorY = 0 // The simulated wall stands on y = 0.
        timer = Timer.publish(every: 1.0 / 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.cancel()
    }

    private func tick() {
        travelled += Self.speed / 15
        let total = Float(MeasureMath.pathLength(Self.route))
        if travelled > total { travelled = 0 }
        let position = Self.position(at: travelled)
        guard let session else { return }
        let cables = session.runs.map(\.points)
        if !session.isAiming {
            placement?.cursor = nil
            session.cursor = nil
            session.guide = nil
            return
        }
        if let placement, placement.isActive {
            // The simulated wall is the x/y plane facing +z: identity rotation.
            var pose = matrix_identity_float4x4
            pose.columns.3 = SIMD4(position, 1)
            let size = FixtureGeometry.size(frameMM: placement.selectedFixtureId.flatMap { catalog[$0] }?.frameMM)
            let connections = placement.connectionPoints(catalog: catalog, cables: cables + [session.points])
            var (snapped, kind) = ConnectionSnapping.snapFixture(pose: pose, size: size, to: connections)
            var alignment = Alignment.none
            if kind == nil {
                let fixture = placement.selectedFixtureId.flatMap { catalog[$0] }
                (snapped, alignment) = AlignmentSnapping.align(
                    pose: snapped, others: placement.placed.map(\.transform), floorY: session.floorY,
                    standardHeight: fixture.flatMap { FixtureGeometry.standardHeight(product: $0.product) })
            }
            placement.cursor = snapped
            placement.guide = kind.map(MeasureGuide.init)
            placement.alignment = alignment
            session.cursor = nil
            session.guide = nil
        } else {
            placement?.cursor = nil
            placement?.guide = nil
            let connections = placement?.connectionPoints(catalog: catalog, cables: cables) ?? []
            let last = session.isFinished || session.pausesRoute ? nil : session.points.last
            let (cursor, guide) = Snapping.cursor(position, last: last, connections: connections)
            session.cursor = cursor
            session.guide = guide
        }
    }

    static func position(at distance: Float) -> SIMD3<Float> {
        var left = distance
        for (a, b) in zip(route, route.dropFirst()) {
            let length = simd_distance(a, b)
            if left <= length { return a + (b - a) * (left / length) }
            left -= length
        }
        return route.last ?? .zero
    }
}

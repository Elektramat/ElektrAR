import Combine
import Foundation
import simd

nonisolated enum MeasureMath {
    /// Sum of straight segments between consecutive points, in meters.
    static func pathLength(_ points: [SIMD3<Float>]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + Double(simd_distance($1.0, $1.1)) }
    }
}

/// A finished cable in a room. Its points are connection points for the next cable, so a
/// second or third cable can branch off it.
nonisolated struct CableRun: Identifiable, Equatable, Sendable {
    let id: UUID
    let cableId: String
    let points: [SIMD3<Float>]

    var length: Double { MeasureMath.pathLength(points) }
}

/// The cable being drawn by hand (anchor points), the finished cables, and the crosshair.
/// A MeasureProvider writes `cursor` and `trackingMessage`; the UI calls addPoint, undo, reset
/// and completeRun.
@MainActor
final class MeasureSession: ObservableObject {
    /// Anchor points of the cable being drawn now.
    @Published private(set) var points: [SIMD3<Float>] = []
    /// Finished cables in this room.
    @Published private(set) var runs: [CableRun] = []
    /// World position under the crosshair, nil when nothing is hit.
    @Published var cursor: SIMD3<Float>?
    /// Dutch hint for the user, nil when tracking is fine.
    @Published var trackingMessage: String?
    /// Set when the cursor is snapped to vertical, level, a switch or an earlier cable.
    @Published var guide: MeasureGuide?
    /// Height of the floor in world space, nil until ARKit has seen it.
    @Published var floorY: Float?
    @Published private(set) var isFinished = false
    /// True when the device measures with LiDAR depth.
    @Published var usesLiDAR = false
    /// Draw with right angles: from the last anchor first straight up or down, then sideways
    /// to the crosshair, the way cable runs along a wall. Off: a straight line.
    @Published var rightAngles = true
    /// Automatic mode: cables the app suggests between the parts, not yet added.
    @Published var proposedRoutes: [[SIMD3<Float>]] = []
    /// Automatic mode: where the cables start (electrical cabinet).
    @Published var startPoint: SIMD3<Float>?
    /// True when the crosshair aims but no live cable segment is drawn (placing the start point).
    @Published var pausesRoute = false
    /// False in the view mode: no crosshair, no cursor, only looking and tapping.
    @Published var isAiming = true
    /// The cable whose info card is open; drawn highlighted.
    @Published var selectedRunId: UUID?
    /// Set by the provider when the user taps a part or a cable; the UI opens its info card.
    @Published var tapped: TapTarget?

    /// How many points each "+" added (1, or 2 with a corner), so undo removes a whole step.
    private var steps: [Int] = []

    var canAddPoint: Bool { !isFinished && cursor != nil }
    var canFinish: Bool { !isFinished && points.count >= 2 }

    var confirmedLength: Double { MeasureMath.pathLength(points) }

    /// The live part of the cable: from the last anchor to the crosshair, with a corner in
    /// between when drawing with right angles. Empty when there is nothing to preview.
    var previewPoints: [SIMD3<Float>] {
        guard !isFinished, !pausesRoute, let cursor, let last = points.last else { return [] }
        return Self.route(from: last, to: cursor, rightAngles: rightAngles)
    }

    /// Confirmed segments plus the live preview to the crosshair.
    var totalLength: Double {
        confirmedLength + MeasureMath.pathLength(previewPoints)
    }

    /// The points from `a` to `b`: with right angles via the corner straight above or below `a`.
    static func route(from a: SIMD3<Float>, to b: SIMD3<Float>, rightAngles: Bool) -> [SIMD3<Float>] {
        guard rightAngles else { return [a, b] }
        let corner = SIMD3(a.x, b.y, a.z)
        guard simd_distance(corner, a) > 0.01, simd_distance(corner, b) > 0.01 else { return [a, b] }
        return [a, corner, b]
    }

    @discardableResult
    func addPoint() -> Bool {
        guard canAddPoint, let cursor else { return false }
        let added = points.last.map { Array(Self.route(from: $0, to: cursor, rightAngles: rightAngles).dropFirst()) }
            ?? [cursor]
        points += added
        steps.append(added.count)
        return true
    }

    /// Removes the last "+" (the point and, with right angles, its corner).
    func undo() {
        isFinished = false
        let count = steps.popLast() ?? 1
        points.removeLast(min(count, points.count))
    }

    /// Clears the cable being drawn; finished cables stay.
    func reset() {
        isFinished = false
        points.removeAll()
        steps.removeAll()
    }

    /// Clears everything, also the finished cables (e.g. opening another room).
    func resetAll() {
        reset()
        runs.removeAll()
        proposedRoutes.removeAll()
        startPoint = nil
        selectedRunId = nil
    }

    func finish() {
        if canFinish { isFinished = true }
    }

    func resume() {
        isFinished = false
    }

    /// Keeps the current cable as a finished one and starts a new, empty one.
    /// Returns the new cable, or nil when there are fewer than two points.
    @discardableResult
    func completeRun(cableId: String) -> CableRun? {
        guard points.count >= 2 else { return nil }
        let run = CableRun(id: UUID(), cableId: cableId, points: points)
        runs.append(run)
        reset()
        return run
    }

    /// Keeps automatically drawn cables as finished cables.
    func addRuns(_ routes: [[SIMD3<Float>]], cableId: String) {
        runs += routes.filter { $0.count >= 2 }.map { CableRun(id: UUID(), cableId: cableId, points: $0) }
    }

    func removeRun(_ id: UUID) {
        runs.removeAll { $0.id == id }
        if selectedRunId == id { selectedRunId = nil }
    }

    /// Replaces everything with a saved room.
    func load(runs: [CableRun], startPoint: SIMD3<Float>?, floorY: Float?) {
        reset()
        self.runs = runs
        self.startPoint = startPoint
        proposedRoutes.removeAll()
        selectedRunId = nil
        if let floorY { self.floorY = floorY }
    }
}

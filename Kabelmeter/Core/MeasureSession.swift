import Combine
import Foundation
import simd

/// How a segment between two points is counted.
nonisolated enum RouteMode: String, CaseIterable, Sendable {
    /// Cable follows the wall: the vertical and horizontal parts are added up.
    case alongWall
    /// Straight line between the points.
    case straight
}

nonisolated enum MeasureMath {
    /// Length of one segment in meters.
    static func segmentLength(_ a: SIMD3<Float>, _ b: SIMD3<Float>, mode: RouteMode) -> Double {
        switch mode {
        case .straight:
            return Double(simd_distance(a, b))
        case .alongWall:
            let d = b - a
            return Double(simd_length(SIMD2(d.x, d.z)) + abs(d.y))
        }
    }

    /// Sum of segments between consecutive points, in meters.
    static func pathLength(_ points: [SIMD3<Float>], mode: RouteMode = .straight) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + segmentLength($1.0, $1.1, mode: mode) }
    }

    /// The lines to draw for one segment: one straight line, or along the wall first
    /// vertical (at `a`) and then horizontal (at the height of `b`). Skips tiny legs.
    static func legs(_ a: SIMD3<Float>, _ b: SIMD3<Float>, mode: RouteMode) -> [(SIMD3<Float>, SIMD3<Float>)] {
        let candidates: [(SIMD3<Float>, SIMD3<Float>)]
        switch mode {
        case .straight:
            candidates = [(a, b)]
        case .alongWall:
            let corner = SIMD3(a.x, b.y, a.z)
            candidates = [(a, corner), (corner, b)]
        }
        return candidates.filter { simd_distance($0.0, $0.1) > 0.001 }
    }
}

/// A cable route that is done (added to the cart). It stays visible and its points are
/// connection points for the next cable, so a second or third cable can branch off it.
nonisolated struct CableRun: Identifiable, Equatable, Sendable {
    let id: UUID
    let cableId: String
    let points: [SIMD3<Float>]

    var length: Double { MeasureMath.pathLength(points) }
}

/// Points, segments and the total length. A MeasureProvider writes `cursor` and
/// `trackingMessage`; the UI calls addPoint, undo, reset and finish.
@MainActor
final class MeasureSession: ObservableObject {
    /// Points of the cable being measured now.
    @Published private(set) var points: [SIMD3<Float>] = []
    /// Cables measured earlier in this session.
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
    /// Along the wall (default) or straight lines.
    @Published var mode: RouteMode = .alongWall
    /// True when the device measures with LiDAR depth.
    @Published var usesLiDAR = false

    var canAddPoint: Bool { !isFinished && cursor != nil }
    var canFinish: Bool { !isFinished && points.count >= 2 }

    var confirmedLength: Double { MeasureMath.pathLength(points, mode: mode) }

    /// Confirmed segments plus the live preview segment to the crosshair.
    var totalLength: Double {
        guard !isFinished, let cursor, let last = points.last else { return confirmedLength }
        return confirmedLength + MeasureMath.segmentLength(last, cursor, mode: mode)
    }

    @discardableResult
    func addPoint() -> Bool {
        guard canAddPoint, let cursor else { return false }
        points.append(cursor)
        return true
    }

    func undo() {
        isFinished = false
        if !points.isEmpty { points.removeLast() }
    }

    /// Clears the cable being measured; earlier cables stay.
    func reset() {
        isFinished = false
        points.removeAll()
    }

    /// Clears everything, also the earlier cables (e.g. a new room in AR).
    func resetAll() {
        reset()
        runs.removeAll()
    }

    func finish() {
        if canFinish { isFinished = true }
    }

    func resume() {
        isFinished = false
    }

    /// Keeps the current route as a finished cable and starts a new, empty one.
    func completeRun(cableId: String) {
        guard points.count >= 2 else { return }
        runs.append(CableRun(id: UUID(), cableId: cableId, points: points))
        reset()
    }
}

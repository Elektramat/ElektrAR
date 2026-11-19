import Combine
import Foundation
import simd

nonisolated enum MeasureMath {
    /// Sum of straight segments between consecutive points, in meters.
    static func pathLength(_ points: [SIMD3<Float>]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + Double(simd_distance($1.0, $1.1)) }
    }
}

/// Points, segments and the total length. A MeasureProvider writes `cursor` and
/// `trackingMessage`; the UI calls addPoint, undo, reset and finish.
@MainActor
final class MeasureSession: ObservableObject {
    @Published private(set) var points: [SIMD3<Float>] = []
    /// World position under the crosshair, nil when nothing is hit.
    @Published var cursor: SIMD3<Float>?
    /// Dutch hint for the user, nil when tracking is fine.
    @Published var trackingMessage: String?
    @Published private(set) var isFinished = false

    var canAddPoint: Bool { !isFinished && cursor != nil }
    var canFinish: Bool { !isFinished && points.count >= 2 }

    var confirmedLength: Double { MeasureMath.pathLength(points) }

    /// Confirmed segments plus the live preview segment to the crosshair.
    var totalLength: Double {
        guard !isFinished, let cursor, let last = points.last else { return confirmedLength }
        return confirmedLength + Double(simd_distance(last, cursor))
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

    func reset() {
        isFinished = false
        points.removeAll()
    }

    func finish() {
        if canFinish { isFinished = true }
    }

    func resume() {
        isFinished = false
    }
}

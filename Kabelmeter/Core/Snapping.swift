import Foundation
import simd

/// Which guide the cursor is snapped to, relative to the last point.
nonisolated enum MeasureGuide: Equatable, Sendable {
    /// Straight up or down from the last point (x and z of the last point).
    case vertical
    /// Level with the last point (same height).
    case level
    /// On a connection point (edge middle) of a placed switch or socket.
    case fixture
    /// On a point of a cable measured earlier.
    case cable

    init(_ kind: ConnectionKind) {
        switch kind {
        case .fixture: self = .fixture
        case .cable: self = .cable
        }
    }

    /// Dutch label for the status pill.
    var label: String {
        switch self {
        case .vertical: "Verticaal"
        case .level: "Waterpas"
        case .fixture: "Vast aan schakelaar"
        case .cable: "Vast aan kabel"
        }
    }
}

/// Helps measuring on walls that ARKit only partly sees (no LiDAR, plain walls).
nonisolated enum Snapping {
    /// A segment within this angle of vertical or horizontal is snapped to it.
    static let snapAngle: Float = 8 * .pi / 180
    /// How close (as an angle seen from the camera) the aim must be to the vertical
    /// guide line to use it when there is no surface hit.
    static let guideAngle: Float = 2.5 * .pi / 180
    /// Below this segment length no snapping, so the first centimeters do not jump.
    static let minimumLength: Float = 0.03

    /// Snaps `point` to vertical or level when the segment from `last` is close to it.
    static func snap(_ point: SIMD3<Float>, from last: SIMD3<Float>) -> (SIMD3<Float>, MeasureGuide?) {
        let d = point - last
        let horizontal = simd_length(SIMD2(d.x, d.z))
        let vertical = abs(d.y)
        guard horizontal + vertical >= minimumLength else { return (point, nil) }
        let tolerance = tan(snapAngle)
        if horizontal <= vertical * tolerance {
            return (SIMD3(last.x, point.y, last.z), .vertical)
        }
        if vertical <= horizontal * tolerance {
            return (SIMD3(point.x, last.y, point.z), .level)
        }
        return (point, nil)
    }

    /// The crosshair position for measuring: a connection point (switch edge or earlier cable)
    /// within reach wins, otherwise vertical/level snapping from the last point.
    static func cursor(_ point: SIMD3<Float>, last: SIMD3<Float>?,
                       connections: [ConnectionPoint]) -> (SIMD3<Float>, MeasureGuide?) {
        if let target = ConnectionSnapping.nearest(to: point, in: connections) {
            return (target.position, MeasureGuide(target.kind))
        }
        guard let last else { return (point, nil) }
        return snap(point, from: last)
    }

    /// The point on the vertical line through `last` that the camera ray aims at,
    /// or nil when the ray does not pass close to that line. Lets the user measure a
    /// height on a wall that ARKit has not detected.
    /// With `maxAngle` nil there is no limit: then it returns the closest point on the
    /// line to the ray, which gives an exact height once the cursor is snapped vertical
    /// (the depth of a wall hit without LiDAR is often wrong, the ray direction is not).
    static func pointOnVerticalGuide(rayOrigin o: SIMD3<Float>, rayDirection direction: SIMD3<Float>,
                                     through last: SIMD3<Float>,
                                     maxAngle: Float? = guideAngle) -> SIMD3<Float>? {
        let d = simd_normalize(direction)
        let up = SIMD3<Float>(0, 1, 0)
        let w0 = o - last
        let b = simd_dot(d, up)
        let denom = 1 - b * b // |d| = |up| = 1
        guard denom > 1e-4 else { return nil } // looking straight up or down the line
        let dw = simd_dot(d, w0)
        let uw = simd_dot(up, w0)
        let t = (b * uw - dw) / denom // along the ray
        let s = (uw - b * dw) / denom // along the vertical line
        guard t > 0.1 else { return nil }
        let onLine = last + up * s
        let onRay = o + d * t
        if let maxAngle, simd_distance(onLine, onRay) / t > tan(maxAngle) { return nil }
        return onLine
    }
}

/// Averages the last few hits so the crosshair does not jitter. A jump larger than
/// `jumpDistance` (aiming at another surface) is followed immediately.
nonisolated struct CursorSmoother: Sendable {
    var window = 5
    var jumpDistance: Float = 0.10
    private var samples: [SIMD3<Float>] = []

    init(window: Int = 5, jumpDistance: Float = 0.10) {
        self.window = window
        self.jumpDistance = jumpDistance
    }

    mutating func add(_ point: SIMD3<Float>) -> SIMD3<Float> {
        if let average = average, simd_distance(average, point) > jumpDistance {
            samples.removeAll()
        }
        samples.append(point)
        if samples.count > window { samples.removeFirst(samples.count - window) }
        return average ?? point
    }

    mutating func reset() { samples.removeAll() }

    private var average: SIMD3<Float>? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(.zero, +) / Float(samples.count)
    }
}

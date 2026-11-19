import Foundation
import simd

/// A point a cable is routed to: a placed fixture, or the start point (electrical cabinet).
nonisolated struct RouteNode: Equatable, Sendable {
    /// Middle of the fixture, or the start point itself.
    let position: SIMD3<Float>
    /// Where the cable enters or leaves: the top edge of a fixture.
    let top: SIMD3<Float>
    /// Wall normal (+Z of the fixture); nil for the start point.
    let normal: SIMD3<Float>?

    static func fixture(transform: simd_float4x4, size: SIMD2<Float>) -> RouteNode {
        RouteNode(position: transform.translation,
                  top: transform.apply(FixtureGeometry.localAnchor(.top, size: size)),
                  normal: transform.axisZ)
    }

    static func point(_ p: SIMD3<Float>) -> RouteNode {
        RouteNode(position: p, top: p, normal: nil)
    }
}

/// Draws cables automatically, the way an installer would: straight up from a point to the
/// horizontal zone near the ceiling, along the wall (through a corner when the next fixture
/// is on another wall), and straight down to the next fixture.
nonisolated enum AutoRouter {
    /// Height of the horizontal cable zone above the floor, in meters.
    static let zoneHeight: Float = 2.25
    /// Without a known floor: this far above the highest of the two points.
    static let zoneWithoutFloor: Float = 0.3
    /// Walls whose normals point this far apart are treated as meeting in a corner.
    private static let cornerCos: Float = 0.7
    /// A corner further away than this from both points is not trusted.
    private static let maxCornerDistance: Float = 8

    static func zoneY(floorY: Float?, _ a: Float, _ b: Float) -> Float {
        if let floorY { return max(floorY + zoneHeight, max(a, b)) }
        return max(a, b) + zoneWithoutFloor
    }

    /// One cable from `a` to `b`.
    static func route(from a: RouteNode, to b: RouteNode, floorY: Float?) -> [SIMD3<Float>] {
        let y = zoneY(floorY: floorY, a.top.y, b.top.y)
        var points = [a.top, SIMD3(a.top.x, y, a.top.z)]
        if let na = a.normal, let nb = b.normal, let corner = corner(a.top, na, b.top, nb) {
            points.append(SIMD3(corner.x, y, corner.y))
        }
        points += [SIMD3(b.top.x, y, b.top.z), b.top]
        return withoutDuplicates(points)
    }

    /// Cables that connect `start` (if any) and then each node, always going to the nearest
    /// node that is not connected yet.
    static func chain(start: RouteNode?, nodes: [RouteNode], floorY: Float?) -> [[SIMD3<Float>]] {
        let order = order(start: start, nodes: nodes)
        var path = order.map { nodes[$0] }
        if let start { path.insert(start, at: 0) }
        return zip(path, path.dropFirst()).map { route(from: $0, to: $1, floorY: floorY) }
    }

    /// The order (indices into `nodes`) in which `chain` visits the nodes.
    static func order(start: RouteNode?, nodes: [RouteNode]) -> [Int] {
        var remaining = Array(nodes.indices)
        var result: [Int] = []
        var current: SIMD3<Float>
        if let start {
            current = start.position
        } else {
            guard let first = remaining.first else { return [] }
            result.append(remaining.removeFirst())
            current = nodes[first].position
        }
        while let index = remaining.indices.min(by: {
            simd_distance(nodes[remaining[$0]].position, current) < simd_distance(nodes[remaining[$1]].position, current)
        }) {
            let next = remaining.remove(at: index)
            result.append(next)
            current = nodes[next].position
        }
        return result
    }

    /// Where two walls meet, seen from above (x, z), or nil for (nearly) parallel walls.
    static func corner(_ pa: SIMD3<Float>, _ na: SIMD3<Float>, _ pb: SIMD3<Float>, _ nb: SIMD3<Float>) -> SIMD2<Float>? {
        let a = SIMD2(na.x, na.z), b = SIMD2(nb.x, nb.z)
        guard simd_length(a) > 1e-3, simd_length(b) > 1e-3 else { return nil }
        let ua = simd_normalize(a), ub = simd_normalize(b)
        guard abs(simd_dot(ua, ub)) < cornerCos else { return nil }
        // Wall lines: p + t * tangent, tangent = normal turned 90 degrees.
        let ta = SIMD2(-ua.y, ua.x), tb = SIMD2(-ub.y, ub.x)
        let p = SIMD2(pa.x, pa.z), q = SIMD2(pb.x, pb.z)
        let denom = ta.x * tb.y - ta.y * tb.x
        guard abs(denom) > 1e-4 else { return nil }
        let d = q - p
        let t = (d.x * tb.y - d.y * tb.x) / denom
        let c = p + ta * t
        guard simd_distance(c, p) < maxCornerDistance, simd_distance(c, q) < maxCornerDistance else { return nil }
        return c
    }

    private static func withoutDuplicates(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        for p in points where result.last.map({ simd_distance($0, p) > 0.001 }) ?? true {
            result.append(p)
        }
        return result
    }
}

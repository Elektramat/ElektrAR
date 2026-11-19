import Foundation
import simd

/// One of the four connection points of a switch or socket: the middle of an edge of its frame.
nonisolated enum FixtureSide: CaseIterable, Sendable {
    case top, bottom, left, right

    var opposite: FixtureSide {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }
}

/// Frame size and connection points of a placed fixture.
nonisolated enum FixtureGeometry {
    /// Used when the catalog has no frame size.
    static let defaultFrameMM: [Double] = [80, 80]

    /// Frame width and height in meters.
    static func size(frameMM: [Double]?) -> SIMD2<Float> {
        let frame = (frameMM?.count == 2 ? frameMM : nil) ?? defaultFrameMM
        return SIMD2(Float(frame[0]) / 1000, Float(frame[1]) / 1000)
    }

    /// Usual height of the middle above the floor in the Netherlands, in meters.
    static func standardHeight(product: String) -> Float? {
        switch product {
        case "schakelaar": 1.05
        case "stopcontact": 0.30
        default: nil
        }
    }

    /// Connection point in the fixture's own space: +X right, +Y up, on the wall (z = 0).
    static func localAnchor(_ side: FixtureSide, size: SIMD2<Float>) -> SIMD3<Float> {
        switch side {
        case .top: [0, size.y / 2, 0]
        case .bottom: [0, -size.y / 2, 0]
        case .left: [-size.x / 2, 0, 0]
        case .right: [size.x / 2, 0, 0]
        }
    }

    /// The four connection points in world space.
    static func anchors(transform: simd_float4x4, size: SIMD2<Float>) -> [(side: FixtureSide, position: SIMD3<Float>)] {
        FixtureSide.allCases.map { ($0, transform.apply(localAnchor($0, size: size))) }
    }
}

/// What the crosshair is attached to.
nonisolated enum ConnectionKind: Equatable, Sendable {
    /// A connection point of a placed switch or socket.
    case fixture
    /// A point of a cable that was measured before.
    case cable
}

nonisolated struct ConnectionPoint: Equatable, Sendable {
    let position: SIMD3<Float>
    let kind: ConnectionKind
    /// Set for fixture points, so a new fixture can line up against the right edge.
    var side: FixtureSide?
    /// Wall normal of the fixture this point belongs to.
    var normal: SIMD3<Float>?
    /// Transform of the fixture this point belongs to.
    var transform: simd_float4x4?
}

/// Makes cables and fixtures click together: a cable end snaps to a connection point of a
/// switch, and a switch snaps with one of its edges to a cable point or to the opposite
/// edge of another switch.
nonisolated enum ConnectionSnapping {
    /// The crosshair snaps to a connection point closer than this, in meters.
    static let distance: Float = 0.06

    /// Connection points of all placed fixtures and all points of earlier cables.
    static func points(fixtures: [(transform: simd_float4x4, size: SIMD2<Float>)],
                       cables: [[SIMD3<Float>]]) -> [ConnectionPoint] {
        var result: [ConnectionPoint] = []
        for fixture in fixtures {
            let normal = fixture.transform.axisZ
            for anchor in FixtureGeometry.anchors(transform: fixture.transform, size: fixture.size) {
                result.append(ConnectionPoint(position: anchor.position, kind: .fixture, side: anchor.side,
                                              normal: normal, transform: fixture.transform))
            }
        }
        for cable in cables {
            for point in cable {
                result.append(ConnectionPoint(position: point, kind: .cable))
            }
        }
        return result
    }

    /// The nearest connection point within `distance` of the crosshair.
    static func nearest(to point: SIMD3<Float>, in points: [ConnectionPoint],
                        within limit: Float = distance) -> ConnectionPoint? {
        var best: ConnectionPoint?
        var bestDistance = limit
        for candidate in points {
            let d = simd_distance(point, candidate.position)
            if d <= bestDistance {
                best = candidate
                bestDistance = d
            }
        }
        return best
    }

    /// Moves a fixture that is about to be placed so that one of its edges touches a
    /// cable point, or the opposite edge of another fixture on the same wall. Returns the
    /// pose unchanged (and nil) when nothing is close.
    static func snapFixture(pose: simd_float4x4, size: SIMD2<Float>, to points: [ConnectionPoint],
                            within limit: Float = distance) -> (simd_float4x4, ConnectionKind?) {
        let normal = pose.axisZ
        var bestDistance = limit
        var best: (simd_float4x4, ConnectionKind)?

        for side in FixtureSide.allCases {
            let local = FixtureGeometry.localAnchor(side, size: size)
            let mine = pose.apply(local)
            for target in points {
                let d = simd_distance(mine, target.position)
                guard d <= bestDistance else { continue }
                switch target.kind {
                case .fixture:
                    // Side by side: only edge to opposite edge, and only on the same wall.
                    guard target.side == side.opposite, let other = target.transform,
                          let otherNormal = target.normal, simd_dot(otherNormal, normal) > 0.9 else { continue }
                    // Take over the other fixture's rotation so the frames line up exactly.
                    var snapped = other
                    snapped.columns.3 = SIMD4(target.position - other.rotate(local), 1)
                    best = (snapped, .fixture)
                case .cable:
                    // Move along the wall only, so the fixture stays flat on it.
                    var delta = target.position - mine
                    delta -= simd_dot(delta, normal) * normal
                    var snapped = pose
                    snapped.columns.3 += SIMD4(delta, 0)
                    best = (snapped, .cable)
                }
                bestDistance = d
            }
        }
        guard let best else { return (pose, nil) }
        return best
    }
}

/// Height above the floor, for the dotted height line.
nonisolated enum FloorHeight {
    /// Height of `point` above the floor, nil when the floor is not known yet.
    static func height(of point: SIMD3<Float>?, floorY: Float?) -> Double? {
        guard let point, let floorY else { return nil }
        return Double(max(0, point.y - floorY))
    }

    /// The floor among horizontal surfaces: the lowest one ARKit calls a floor, otherwise the
    /// lowest one at least `minimumDrop` below the camera (tables and seats are higher).
    static func floorY(planes: [(y: Float, isFloor: Bool)], cameraY: Float, minimumDrop: Float = 0.8) -> Float? {
        if let floor = planes.filter(\.isFloor).map(\.y).min() { return floor }
        return planes.map(\.y).filter { $0 <= cameraY - minimumDrop }.min()
    }
}

nonisolated extension simd_float4x4 {
    func apply(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let p = self * SIMD4(point, 1)
        return SIMD3(p.x, p.y, p.z)
    }

    func rotate(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        let p = self * SIMD4(vector, 0)
        return SIMD3(p.x, p.y, p.z)
    }

    var axisX: SIMD3<Float> { SIMD3(columns.0.x, columns.0.y, columns.0.z) }

    var axisY: SIMD3<Float> { SIMD3(columns.1.x, columns.1.y, columns.1.z) }

    var axisZ: SIMD3<Float> { SIMD3(columns.2.x, columns.2.y, columns.2.z) }

    var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
}

/// What the user tapped: a placed fixture or a cable.
nonisolated enum TapTarget: Equatable, Sendable {
    case fixture(UUID)
    case cable(UUID)
}

/// Finds what a tap on the screen hits, from the screen positions of fixtures and cable points
/// (nil positions are behind the camera or off screen).
nonisolated enum TapHit {
    /// A fixture is hit within this many points of its middle.
    static let fixtureRadius: Double = 44
    /// A cable is hit within this many points of one of its segments.
    static let cableRadius: Double = 28

    static func target(at tap: SIMD2<Double>, fixtures: [(id: UUID, screen: SIMD2<Double>?)],
                       cables: [(id: UUID, screen: [SIMD2<Double>?])]) -> TapTarget? {
        let fixture = fixtures.compactMap { item in item.screen.map { (item.id, simd_distance($0, tap)) } }
            .min { $0.1 < $1.1 }
        if let fixture, fixture.1 <= fixtureRadius { return .fixture(fixture.0) }
        var best: (UUID, Double)?
        for cable in cables {
            for (a, b) in zip(cable.screen, cable.screen.dropFirst()) {
                guard let a, let b else { continue }
                let d = distance(tap, segment: a, b)
                if d <= cableRadius, d < (best?.1 ?? .infinity) { best = (cable.id, d) }
            }
        }
        return best.map { .cable($0.0) }
    }

    static func distance(_ p: SIMD2<Double>, segment a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let lengthSquared = simd_length_squared(ab)
        guard lengthSquared > 1e-9 else { return simd_distance(p, a) }
        let t = min(max(simd_dot(p - a, ab) / lengthSquared, 0), 1)
        return simd_distance(p, a + ab * t)
    }
}

/// What a part being placed lines up with. Only within a few centimeters (`AlignmentSnapping.distance`),
/// so putting a part half a meter higher on purpose just works.
nonisolated struct Alignment: Equatable, Sendable {
    /// Middle of the part this one is level with (same height).
    var level: SIMD3<Float>?
    /// Middle of the part this one is straight above or below.
    var vertical: SIMD3<Float>?
    /// The standard height above the floor it sits at, in meters.
    var standardHeight: Float?

    static let none = Alignment()

    var isEmpty: Bool { level == nil && vertical == nil && standardHeight == nil }

    /// Dutch label for the status pill.
    var label: String? {
        if level != nil, vertical != nil { return "Waterpas én recht boven elkaar" }
        if level != nil { return "Waterpas met ander onderdeel" }
        if vertical != nil { return "Recht boven of onder ander onderdeel" }
        if let standardHeight { return "Standaardhoogte \(Format.height(Double(standardHeight)))" }
        return nil
    }
}

/// Lines up a part being placed with the parts already on the same wall (level, or straight
/// above/below), or with the standard height for its kind. The dotted guide lines show it.
nonisolated enum AlignmentSnapping {
    /// Within this distance the part is pulled onto the line, in meters.
    static let distance: Float = 0.04

    static func align(pose: simd_float4x4, others: [simd_float4x4], floorY: Float?, standardHeight: Float?,
                      within tolerance: Float = distance) -> (simd_float4x4, Alignment) {
        let normal = pose.axisZ, right = pose.axisX, up = pose.axisY
        var result = pose
        var alignment = Alignment()
        var bestY = tolerance, bestX = tolerance
        for other in others where simd_dot(other.axisZ, normal) > 0.9 {
            let d = other.translation - pose.translation
            let dy = abs(simd_dot(d, up)), dx = abs(simd_dot(d, right))
            if dy < bestY { bestY = dy; alignment.level = other.translation }
            if dx < bestX { bestX = dx; alignment.vertical = other.translation }
        }
        if let level = alignment.level {
            result.columns.3 += SIMD4(up * simd_dot(level - pose.translation, up), 0)
        } else if let floorY, let standardHeight, abs(up.y) > 0.5 {
            let dy = (floorY + standardHeight) - pose.translation.y
            if abs(dy) < tolerance {
                result.columns.3 += SIMD4(up * (dy / up.y), 0)
                alignment.standardHeight = standardHeight
            }
        }
        if let vertical = alignment.vertical {
            result.columns.3 += SIMD4(right * simd_dot(vertical - result.translation, right), 0)
        }
        return (result, alignment)
    }
}

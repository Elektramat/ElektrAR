import ARKit
import Combine
import QuartzCore
import RealityKit
import UIKit

/// Real measuring with ARKit + RealityKit. A few times per second it finds the world
/// point under the crosshair and draws points, segments and the live preview.
/// In the "Schakelaars plaatsen" mode it hands the crosshair to `ARFixturePlacer`.
///
/// Two paths:
/// - LiDAR (Pro models): read the smoothed LiDAR depth at the crosshair, then raycast
///   against the estimated surface (which also uses LiDAR). Works on plain walls.
/// - No LiDAR: raycast against detected planes, then estimated planes, then detected
///   walls extended infinitely.
/// Both: snapped vertical segments take their height from the camera ray, not from
/// the hit depth.
@MainActor
final class ARMeasureProvider: MeasureProvider {
    let arView: ARView

    private weak var session: MeasureSession?
    private weak var placement: PlacementSession?
    private let placer: ARFixturePlacer
    private let catalog: [String: Fixture]
    private let heightLine = HeightLine()
    private var newRoomSubscription: AnyCancellable?
    private let root = AnchorEntity(world: .zero)
    private let previewLegs: [ModelEntity]
    private var hasLiDAR = false
    private let verticalGuide: ModelEntity
    private var smoother = CursorSmoother()
    private var lastHitTime: CFTimeInterval = 0
    /// Keep the last cursor this long when ARKit briefly loses the surface.
    private static let holdDuration: CFTimeInterval = 0.5
    private var placed: [Entity] = []
    private var runEntities: [Entity] = []
    private var updateSubscription: Cancellable?
    private var pointsSubscription: AnyCancellable?
    private var runsSubscription: AnyCancellable?
    private var lastTick: CFTimeInterval = 0
    private static let tickInterval: CFTimeInterval = 1.0 / 15
    /// ARKit ambient intensity in lumen; ~1000 is a well lit room.
    private static let darkThreshold: CGFloat = 150

    init(fixtures: [Fixture]) {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        placer = ARFixturePlacer(arView: arView, fixtures: fixtures)
        catalog = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        previewLegs = (0..<2).map { _ in Self.makeSegmentEntity(color: Theme.arPreview) }
        for leg in previewLegs {
            leg.isEnabled = false
            root.addChild(leg)
        }
        verticalGuide = Self.makeSegmentEntity(color: Theme.arGuide, thickness: 0.002)
        verticalGuide.isEnabled = false
        root.addChild(verticalGuide)
        root.addChild(heightLine.entity)
        arView.scene.addAnchor(root)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)
    }

    func start(session: MeasureSession, placement: PlacementSession) {
        self.session = session
        self.placement = placement
        guard ARWorldTrackingConfiguration.isSupported else {
            session.trackingMessage = TrackingText.unavailable
            return
        }
        let config = Self.makeConfiguration()
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        session.usesLiDAR = hasLiDAR
        placer.prepare(config, placement: placement)
        arView.session.run(config)
        newRoomSubscription = placement.newRoomRequests.sink { [weak self] in self?.startNewRoom() }

        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        pointsSubscription = session.$points.combineLatest(session.$mode).sink { [weak self] points, mode in
            self?.render(points: points, mode: mode)
        }
        runsSubscription = session.$runs.sink { [weak self] runs in
            self?.render(runs: runs)
        }
    }

    func stop() {
        updateSubscription?.cancel()
        pointsSubscription?.cancel()
        runsSubscription?.cancel()
        newRoomSubscription?.cancel()
        placer.flush()
        arView.session.pause()
    }

    private static func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        return config
    }

    /// Drops the saved room and starts tracking from scratch. Measured points belong
    /// to the old coordinate system, so they go too.
    private func startNewRoom() {
        placer.removeAll()
        smoother.reset()
        session?.resetAll()
        session?.floorY = nil
        arView.session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: Per-frame work (throttled)

    private func tick() {
        let now = CACurrentMediaTime()
        guard now - lastTick >= Self.tickInterval, let session else { return }
        lastTick = now

        let frame = arView.session.currentFrame
        updateFloor(frame: frame, session: session)
        let cables = session.runs.map(\.points)
        if let placement {
            // A new switch may click onto any cable point, also of the cable being measured.
            placer.tick(frame: frame, connections: placement.connectionPoints(catalog: catalog,
                                                                             cables: cables + [session.points]))
        }

        // Placing switches: the placer owns the crosshair, measuring pauses.
        if let placement, placement.isActive {
            heightLine.update(at: placement.cursor?.translation, floorY: session.floorY)
            let message = Self.message(for: frame?.camera.trackingState)
                ?? (placement.cursor == nil ? TrackingText.aimAtWall : nil)
            if session.trackingMessage != message { session.trackingMessage = message }
            if session.guide != nil { session.guide = nil }
            if session.cursor != nil { session.cursor = nil }
            smoother.reset()
            updatePreview(from: nil, to: nil, mode: session.mode)
            updateVerticalGuide(through: nil)
            return
        }

        let last = session.isFinished ? nil : session.points.last
        var message = Self.message(for: frame?.camera.trackingState)
        var cursor: SIMD3<Float>?
        var guide: MeasureGuide?
        var onConnection = false

        if message == nil {
            let ray = rayFromCenter()
            var candidate: SIMD3<Float>?
            if let frame, hasLiDAR {
                candidate = depthPoint(frame: frame, ray: ray) ?? raycastFromCenter()
            } else {
                candidate = raycastFromCenter()
            }

            if let hit = candidate {
                lastHitTime = now
                // A connection point (switch edge, earlier cable) within reach wins; otherwise
                // vertical/level snapping from the last point.
                let connections = placement?.connectionPoints(catalog: catalog, cables: cables) ?? []
                if let target = ConnectionSnapping.nearest(to: hit, in: connections) {
                    candidate = target.position
                    guide = MeasureGuide(target.kind)
                    onConnection = true
                } else if let last {
                    var (snapped, snapGuide) = Snapping.snap(hit, from: last)
                    // Vertical: the height comes from where the ray passes the vertical line,
                    // which does not depend on the (often wrong) depth of the hit.
                    if snapGuide == .vertical, let ray,
                       let exact = Snapping.pointOnVerticalGuide(rayOrigin: ray.origin, rayDirection: ray.direction,
                                                                 through: last, maxAngle: nil) {
                        snapped = exact
                    }
                    candidate = snapped
                    guide = snapGuide
                }
            } else if let last, let ray,
                      let onGuide = Snapping.pointOnVerticalGuide(rayOrigin: ray.origin, rayDirection: ray.direction,
                                                                  through: last) {
                // No surface hit: aim along the vertical line through the last point.
                lastHitTime = now
                candidate = onGuide
                guide = .vertical
            }

            if let candidate {
                // A connection point is exact: smoothing would leave the cursor next to it.
                cursor = onConnection ? candidate : smoother.add(candidate)
                if let light = frame?.lightEstimate, light.ambientIntensity < Self.darkThreshold {
                    message = TrackingText.tooDark
                }
            } else if now - lastHitTime < Self.holdDuration {
                cursor = session.cursor
                guide = session.guide
            } else {
                smoother.reset()
                message = TrackingText.moveSideways
            }
        } else {
            smoother.reset()
        }

        if session.trackingMessage != message { session.trackingMessage = message }
        if session.guide != guide { session.guide = guide }
        session.cursor = cursor
        updatePreview(from: last, to: cursor, mode: session.mode)
        updateVerticalGuide(through: guide == .vertical ? last : nil)
        heightLine.update(at: cursor, floorY: session.floorY)
    }

    /// The floor is the lowest horizontal plane ARKit calls a floor, or else the lowest one
    /// well below the camera. Only goes down over time, so a table seen later does not win.
    private func updateFloor(frame: ARFrame?, session: MeasureSession) {
        guard let frame else { return }
        let planes = frame.anchors.compactMap { anchor -> (y: Float, isFloor: Bool)? in
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { return nil }
            let isFloor = ARPlaneAnchor.isClassificationSupported && plane.classification == .floor
            return (plane.transform.columns.3.y, isFloor)
        }
        guard let floor = FloorHeight.floorY(planes: planes, cameraY: frame.camera.transform.columns.3.y) else {
            return
        }
        if session.floorY.map({ abs($0 - floor) > 0.005 }) ?? true { session.floorY = floor }
    }

    private static func message(for state: ARCamera.TrackingState?) -> String? {
        switch state {
        case .normal: return nil
        case .limited(.relocalizing): return TrackingText.relocalizing
        case .limited(.insufficientFeatures): return TrackingText.aimAtSurface
        case .limited, .notAvailable, .none: return TrackingText.moveSlowly
        }
    }

    private func raycastFromCenter() -> SIMD3<Float>? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let hit: ARRaycastResult?
        if hasLiDAR {
            // The estimated surface uses the LiDAR mesh and depth: best first.
            hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
                ?? arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .any).first
        } else {
            // 1. Detected plane within its bounds (most accurate without depth).
            // 2. Estimated surface from feature points.
            // 3. Detected wall extended infinitely: a wall ARKit only saw partly.
            //    Risk: past a corner this can hit the extension of another wall.
            hit = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .any).first
                ?? arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
                ?? arView.raycast(from: center, allowing: .existingPlaneInfinite, alignment: .vertical).first
        }
        guard let t = hit?.worldTransform else { return nil }
        return SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    /// LiDAR: the world point at the crosshair from the smoothed depth map. Uses the
    /// 3x3 center pixels with high confidence; nil when too few are reliable.
    private func depthPoint(frame: ARFrame,
                            ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)?) -> SIMD3<Float>? {
        guard let ray, let depth = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let confidence = depth.confidenceMap else { return nil }
        let map = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(map),
              let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        guard width > 2, height > 2,
              CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height else { return nil }
        let depthRow = CVPixelBufferGetBytesPerRow(map)
        let confidenceRow = CVPixelBufferGetBytesPerRow(confidence)

        var sum: Float = 0
        var count = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let x = width / 2 + dx, y = height / 2 + dy
                let level = confidenceBase.load(fromByteOffset: y * confidenceRow + x, as: UInt8.self)
                guard level >= UInt8(ARConfidenceLevel.high.rawValue) else { continue }
                let d = depthBase.load(fromByteOffset: y * depthRow + x * 4, as: Float32.self)
                if d.isFinite, d > 0.1, d < 5 {
                    sum += d
                    count += 1
                }
            }
        }
        guard count >= 5 else { return nil }

        // Depth is the distance along the camera's viewing axis, not along the ray.
        let c = frame.camera.transform.columns.2
        let forward = -SIMD3(c.x, c.y, c.z)
        let direction = simd_normalize(ray.direction)
        let cosine = simd_dot(direction, forward)
        guard cosine > 0.2 else { return nil }
        return ray.origin + direction * ((sum / Float(count)) / cosine)
    }

    private func rayFromCenter() -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return arView.ray(through: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    // MARK: Drawing

    private func render(points: [SIMD3<Float>], mode: RouteMode) {
        placed.forEach { $0.removeFromParent() }
        placed.removeAll()
        for point in points {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.008),
                                  materials: [UnlitMaterial(color: Theme.arPoint)])
            dot.position = point
            root.addChild(dot)
            placed.append(dot)
        }
        for (a, b) in zip(points, points.dropFirst()) {
            for (from, to) in MeasureMath.legs(a, b, mode: mode) {
                let segment = Self.makeSegmentEntity(color: Theme.arSegment)
                Self.place(segment, from: from, to: to)
                root.addChild(segment)
                placed.append(segment)
            }
        }
    }

    /// Cables added earlier: drawn thinner and in a calmer color than the cable being measured.
    private func render(runs: [CableRun]) {
        runEntities.forEach { $0.removeFromParent() }
        runEntities.removeAll()
        for run in runs {
            for point in run.points {
                let dot = ModelEntity(mesh: .generateSphere(radius: 0.006),
                                      materials: [UnlitMaterial(color: Theme.arRun)])
                dot.position = point
                root.addChild(dot)
                runEntities.append(dot)
            }
            for (a, b) in zip(run.points, run.points.dropFirst()) {
                let segment = Self.makeSegmentEntity(color: Theme.arRun, thickness: 0.003)
                Self.place(segment, from: a, to: b)
                root.addChild(segment)
                runEntities.append(segment)
            }
        }
    }

    private func updatePreview(from start: SIMD3<Float>?, to end: SIMD3<Float>?, mode: RouteMode) {
        let legs = (start != nil && end != nil) ? MeasureMath.legs(start!, end!, mode: mode) : []
        for (index, entity) in previewLegs.enumerated() {
            if index < legs.count {
                Self.place(entity, from: legs[index].0, to: legs[index].1)
                entity.isEnabled = true
            } else {
                entity.isEnabled = false
            }
        }
    }

    /// A long thin line through the last point while the cursor is snapped to vertical.
    private func updateVerticalGuide(through point: SIMD3<Float>?) {
        guard let point else {
            verticalGuide.isEnabled = false
            return
        }
        Self.place(verticalGuide, from: point - [0, 1.5, 0], to: point + [0, 3, 0])
        verticalGuide.isEnabled = true
    }

    /// A 1 m tall thin box, scaled along y to the segment length.
    private static func makeSegmentEntity(color: UIColor, thickness: Float = 0.004) -> ModelEntity {
        ModelEntity(mesh: .generateBox(width: thickness, height: 1, depth: thickness),
                    materials: [UnlitMaterial(color: color)])
    }

    private static func place(_ entity: Entity, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let d = b - a
        let length = simd_length(d)
        guard length > 0 else { return }
        entity.position = (a + b) / 2
        entity.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
        entity.scale = [1, length, 1]
    }
}

/// Dotted vertical line from the crosshair down to the floor, so the user sees the height.
@MainActor
private final class HeightLine {
    let entity = Entity()
    private var dashes: [ModelEntity] = []
    private static let dash: Float = 0.02
    private static let period: Float = 0.04
    private static let maxHeight: Float = 3.2

    init() {
        let count = Int(Self.maxHeight / Self.period)
        for _ in 0..<count {
            let dash = ModelEntity(mesh: .generateBox(width: 0.003, height: Self.dash, depth: 0.003),
                                   materials: [UnlitMaterial(color: Theme.arHeight)])
            dash.isEnabled = false
            entity.addChild(dash)
            dashes.append(dash)
        }
    }

    /// Shows dashes from the floor up to `point`; hides the line without a point or floor.
    func update(at point: SIMD3<Float>?, floorY: Float?) {
        guard let point, let floorY, point.y > floorY + 0.05 else {
            entity.isEnabled = false
            return
        }
        entity.isEnabled = true
        entity.position = [point.x, floorY, point.z]
        let height = point.y - floorY
        for (i, dash) in dashes.enumerated() {
            let bottom = Float(i) * Self.period
            let visible = bottom + Self.dash <= height
            if dash.isEnabled != visible { dash.isEnabled = visible }
            if visible { dash.position = [0, bottom + Self.dash / 2, 0] }
        }
    }
}

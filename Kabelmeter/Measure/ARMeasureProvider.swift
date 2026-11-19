import ARKit
import Combine
import QuartzCore
import RealityKit
import UIKit

/// Real measuring with ARKit + RealityKit. Raycasts from the screen center a few
/// times per second and draws points, segments and the live preview segment.
/// In the "Schakelaars plaatsen" mode it hands the crosshair to `ARFixturePlacer`.
@MainActor
final class ARMeasureProvider: MeasureProvider {
    let arView: ARView

    private weak var session: MeasureSession?
    private weak var placement: PlacementSession?
    private let placer: ARFixturePlacer
    private var newRoomSubscription: AnyCancellable?
    private let root = AnchorEntity(world: .zero)
    private let preview: ModelEntity
    private let verticalGuide: ModelEntity
    private var smoother = CursorSmoother()
    private var lastHitTime: CFTimeInterval = 0
    /// Keep the last cursor this long when ARKit briefly loses the surface.
    private static let holdDuration: CFTimeInterval = 0.5
    private var placed: [Entity] = []
    private var updateSubscription: Cancellable?
    private var pointsSubscription: AnyCancellable?
    private var lastTick: CFTimeInterval = 0
    private static let tickInterval: CFTimeInterval = 1.0 / 15
    /// ARKit ambient intensity in lumen; ~1000 is a well lit room.
    private static let darkThreshold: CGFloat = 150

    init(fixtures: [Fixture]) {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        placer = ARFixturePlacer(arView: arView, fixtures: fixtures)
        preview = Self.makeSegmentEntity(color: Theme.arPreview)
        preview.isEnabled = false
        root.addChild(preview)
        verticalGuide = Self.makeSegmentEntity(color: Theme.arGuide, thickness: 0.002)
        verticalGuide.isEnabled = false
        root.addChild(verticalGuide)
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
        placer.prepare(config, placement: placement)
        arView.session.run(config)
        newRoomSubscription = placement.newRoomRequests.sink { [weak self] in self?.startNewRoom() }

        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        pointsSubscription = session.$points.sink { [weak self] points in
            self?.render(points: points)
        }
    }

    func stop() {
        updateSubscription?.cancel()
        pointsSubscription?.cancel()
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
        return config
    }

    /// Drops the saved room and starts tracking from scratch. Measured points belong
    /// to the old coordinate system, so they go too.
    private func startNewRoom() {
        placer.removeAll()
        smoother.reset()
        session?.reset()
        arView.session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: Per-frame work (throttled)

    private func tick() {
        let now = CACurrentMediaTime()
        guard now - lastTick >= Self.tickInterval, let session else { return }
        lastTick = now

        let frame = arView.session.currentFrame
        placer.tick(frame: frame)

        // Placing switches: the placer owns the crosshair, measuring pauses.
        if let placement, placement.isActive {
            let message = Self.message(for: frame?.camera.trackingState)
                ?? (placement.cursor == nil ? TrackingText.aimAtWall : nil)
            if session.trackingMessage != message { session.trackingMessage = message }
            if session.guide != nil { session.guide = nil }
            if session.cursor != nil { session.cursor = nil }
            smoother.reset()
            updatePreview(from: nil, to: nil)
            updateVerticalGuide(through: nil)
            return
        }

        let last = session.isFinished ? nil : session.points.last
        var message = Self.message(for: frame?.camera.trackingState)
        var cursor: SIMD3<Float>?
        var guide: MeasureGuide?

        if message == nil {
            var raw = raycastFromCenter()
            // No surface hit: aim along the vertical line through the last point.
            if raw == nil, let last, let ray = rayFromCenter(),
               let onGuide = Snapping.pointOnVerticalGuide(rayOrigin: ray.origin, rayDirection: ray.direction,
                                                           through: last) {
                raw = onGuide
            }

            if let raw {
                lastHitTime = now
                let smooth = smoother.add(raw)
                if let last {
                    (cursor, guide) = Snapping.snap(smooth, from: last)
                } else {
                    cursor = smooth
                }
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
        updatePreview(from: last, to: cursor)
        updateVerticalGuide(through: guide == .vertical ? last : nil)
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
        // 1. Detected plane within its bounds (most accurate).
        // 2. Estimated surface (uses LiDAR depth on Pro models).
        // 3. Detected plane extended infinitely: a wall ARKit only saw partly.
        let hit = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .any).first
            ?? arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
            ?? arView.raycast(from: center, allowing: .existingPlaneInfinite, alignment: .vertical).first
        guard let t = hit?.worldTransform else { return nil }
        return SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    private func rayFromCenter() -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return arView.ray(through: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    // MARK: Drawing

    private func render(points: [SIMD3<Float>]) {
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
            let segment = Self.makeSegmentEntity(color: Theme.arSegment)
            Self.place(segment, from: a, to: b)
            root.addChild(segment)
            placed.append(segment)
        }
    }

    private func updatePreview(from start: SIMD3<Float>?, to end: SIMD3<Float>?) {
        guard let start, let end, simd_distance(start, end) > 0.005 else {
            preview.isEnabled = false
            return
        }
        Self.place(preview, from: start, to: end)
        preview.isEnabled = true
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

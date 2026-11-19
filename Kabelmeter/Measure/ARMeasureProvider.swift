import ARKit
import Combine
import QuartzCore
import RealityKit
import UIKit

/// Real measuring with ARKit + RealityKit. Raycasts from the screen center a few
/// times per second and draws points, segments and the live preview segment.
@MainActor
final class ARMeasureProvider: MeasureProvider {
    let arView: ARView

    private weak var session: MeasureSession?
    private let root = AnchorEntity(world: .zero)
    private let preview: ModelEntity
    private var placed: [Entity] = []
    private var updateSubscription: Cancellable?
    private var pointsSubscription: AnyCancellable?
    private var lastTick: CFTimeInterval = 0
    private static let tickInterval: CFTimeInterval = 1.0 / 15
    /// ARKit ambient intensity in lumen; ~1000 is a well lit room.
    private static let darkThreshold: CGFloat = 150

    init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        preview = Self.makeSegmentEntity(color: Theme.arPreview)
        preview.isEnabled = false
        root.addChild(preview)
        arView.scene.addAnchor(root)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)
    }

    func start(session: MeasureSession) {
        self.session = session
        guard ARWorldTrackingConfiguration.isSupported else {
            session.trackingMessage = TrackingText.unavailable
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config)

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
        arView.session.pause()
    }

    // MARK: Per-frame work (throttled)

    private func tick() {
        let now = CACurrentMediaTime()
        guard now - lastTick >= Self.tickInterval, let session else { return }
        lastTick = now

        let frame = arView.session.currentFrame
        var message = Self.message(for: frame?.camera.trackingState)
        var cursor: SIMD3<Float>?
        if message == nil {
            cursor = raycastFromCenter()
            if cursor == nil {
                message = TrackingText.aimAtSurface
            } else if let light = frame?.lightEstimate, light.ambientIntensity < Self.darkThreshold {
                message = TrackingText.tooDark
            }
        }

        if session.trackingMessage != message { session.trackingMessage = message }
        session.cursor = cursor
        updatePreview(from: session.points.last, to: session.isFinished ? nil : cursor)
    }

    private static func message(for state: ARCamera.TrackingState?) -> String? {
        switch state {
        case .normal: return nil
        case .limited(.insufficientFeatures): return TrackingText.aimAtSurface
        case .limited, .notAvailable, .none: return TrackingText.moveSlowly
        }
    }

    private func raycastFromCenter() -> SIMD3<Float>? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let hit = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .any).first
            ?? arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
        guard let t = hit?.worldTransform else { return nil }
        return SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
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

    /// A 1 m tall thin box, scaled along y to the segment length.
    private static func makeSegmentEntity(color: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateBox(width: 0.004, height: 1, depth: 0.004),
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

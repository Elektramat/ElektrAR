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
    private let catalog: [String: Fixture]
    private let heightLine = DashedLine(color: Theme.arHeight)
    private let levelGuide = DashedLine(color: Theme.arAlign)
    private let aboveGuide = DashedLine(color: Theme.arAlign)
    private var skipSubscription: AnyCancellable?
    private var tapHandler: TapHandler?
    private let root = AnchorEntity(world: .zero)
    /// The live cable to the crosshair: up to two segments (a corner with right angles).
    private let preview: [ModelEntity]
    private let verticalGuide: ModelEntity
    private var smoother = CursorSmoother()
    private var lastHitTime: CFTimeInterval = 0
    /// Keep the last cursor this long when ARKit briefly loses the surface.
    private static let holdDuration: CFTimeInterval = 0.5
    private var placed: [Entity] = []
    private var runEntities: [Entity] = []
    private var proposedEntities: [Entity] = []
    private let highlight = Entity()
    /// A saved design waiting until ARKit has recognised its room.
    private var pendingProject: Project?
    private var projectSubscription: AnyCancellable?
    private var proposedSubscription: AnyCancellable?
    private var updateSubscription: Cancellable?
    private var pointsSubscription: AnyCancellable?
    private var runsSubscription: AnyCancellable?
    private var lastTick: CFTimeInterval = 0
    private static let tickInterval: CFTimeInterval = 1.0 / 15
    /// ARKit ambient intensity in lumen; ~1000 is a well lit room.
    private static let darkThreshold: CGFloat = 150

    /// `mapURL`: where the room is saved (the open room's map).
    init(fixtures: [Fixture], mapURL: URL?) {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        placer = ARFixturePlacer(arView: arView, fixtures: fixtures)
        placer.mapURL = mapURL
        catalog = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        preview = (0..<2).map { _ in Self.makeSegmentEntity(color: Theme.arPreview) }
        for segment in preview {
            segment.isEnabled = false
            root.addChild(segment)
        }
        verticalGuide = Self.makeSegmentEntity(color: Theme.arGuide, thickness: 0.002)
        verticalGuide.isEnabled = false
        root.addChild(verticalGuide)
        root.addChild(heightLine.entity)
        root.addChild(levelGuide.entity)
        root.addChild(aboveGuide.entity)
        let plate = ModelEntity(mesh: .generateBox(size: 1),
                                materials: [UnlitMaterial(color: Theme.arHighlight)])
        plate.components.set(OpacityComponent(opacity: 0.45))
        highlight.addChild(plate)
        highlight.isEnabled = false
        root.addChild(highlight)
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
        placer.prepare(placement: placement)
        arView.session.run(Self.makeConfiguration())
        skipSubscription = placement.skipRestoreRequests.sink { [weak self] in self?.skipRestore() }
        let tap = TapHandler { [weak self] point in self?.handleTap(at: point) }
        arView.addGestureRecognizer(UITapGestureRecognizer(target: tap, action: #selector(TapHandler.tapped(_:))))
        tapHandler = tap

        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        pointsSubscription = session.$points.sink { [weak self] points in
            self?.render(points: points)
        }
        runsSubscription = session.$runs.combineLatest(session.$selectedRunId).sink { [weak self] runs, selected in
            self?.render(runs: runs, selected: selected)
            self?.placer.markDirty()
        }
        proposedSubscription = session.$proposedRoutes.combineLatest(session.$startPoint).sink { [weak self] routes, start in
            self?.renderProposed(routes: routes, start: start)
        }
        projectSubscription = placement.$pendingLoad.compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] load in
                self?.placement?.pendingLoad = nil
                self?.open(load)
            }
    }

    func stop() {
        updateSubscription?.cancel()
        pointsSubscription?.cancel()
        runsSubscription?.cancel()
        proposedSubscription?.cancel()
        projectSubscription?.cancel()
        skipSubscription?.cancel()
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

    /// The saved room is not recognised: start tracking from scratch and show the design
    /// relative to where the user stands now.
    private func skipRestore() {
        smoother.reset()
        session?.floorY = nil
        arView.session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        placement?.isRestoring = false
        if let project = pendingProject {
            pendingProject = nil
            apply(project)
        }
    }

    /// Opens a saved design. With a saved room, ARKit first has to recognise it; until then
    /// the design waits, because its coordinates only fit that room.
    private func open(_ load: ProjectLoad) {
        guard let session, let placement else { return }
        placer.removeAll()
        smoother.reset()
        session.resetAll()
        placement.clearAll()
        if let url = load.mapURL, let map = ARFixturePlacer.loadMap(at: url) {
            // The design's own placements are added again once the room is recognised.
            map.anchors = map.anchors.filter { $0.name?.hasPrefix(ARFixturePlacer.anchorPrefix) != true }
            let config = Self.makeConfiguration()
            config.initialWorldMap = map
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            placement.isRestoring = true
            pendingProject = load.project
        } else {
            apply(load.project)
        }
    }

    private func apply(_ project: Project) {
        session?.load(runs: project.cableRuns, startPoint: project.startPoint.map(Project.point),
                      floorY: project.floorY)
        placement?.load(project.placedFixtures, cabled: project.cabled, roomId: project.id)
    }

    // MARK: Tapping

    /// Tells the UI which fixture or cable was tapped, from their positions on screen.
    private func handleTap(at point: CGPoint) {
        guard let session, let placement, placement.loadedRoomId != nil else { return }
        let screen = { [arView] (p: SIMD3<Float>) -> SIMD2<Double>? in
            guard let s = arView.project(p) else { return nil }
            return SIMD2(Double(s.x), Double(s.y))
        }
        let target = TapHit.target(at: SIMD2(Double(point.x), Double(point.y)),
                                    fixtures: placement.placed.map { ($0.id, screen($0.position)) },
                                    cables: session.runs.map { ($0.id, $0.points.map(screen)) })
        session.tapped = target
    }

    // MARK: Per-frame work (throttled)

    private func tick() {
        let now = CACurrentMediaTime()
        guard now - lastTick >= Self.tickInterval, let session else { return }
        lastTick = now

        let frame = arView.session.currentFrame
        if let project = pendingProject, placement?.isRestoring == false {
            pendingProject = nil
            apply(project)
        }
        updateFloor(frame: frame, session: session)
        updateHighlight()
        let cables = session.runs.map(\.points)
        if let placement {
            // A new switch may click onto any cable point, also of the cable being measured.
            placer.tick(frame: frame, connections: placement.connectionPoints(catalog: catalog,
                                                                             cables: cables + [session.points]),
                        floorY: session.floorY)
        }

        // Only looking: no crosshair, no preview.
        if !session.isAiming {
            if session.cursor != nil { session.cursor = nil }
            if session.guide != nil { session.guide = nil }
            let message = Self.message(for: frame?.camera.trackingState)
            if session.trackingMessage != message { session.trackingMessage = message }
            smoother.reset()
            updatePreview([])
            updateVerticalGuide(through: nil)
            updateHeightLine(at: nil, floorY: nil)
            updateAlignmentGuides(nil, cursor: nil)
            return
        }

        // Placing parts: the placer owns the crosshair, measuring pauses.
        if let placement, placement.isActive {
            updateHeightLine(at: placement.cursor?.translation, floorY: session.floorY)
            updateAlignmentGuides(placement.alignment, cursor: placement.cursor)
            let message = Self.message(for: frame?.camera.trackingState)
                ?? (placement.cursor == nil ? TrackingText.aimAtWall : nil)
            if session.trackingMessage != message { session.trackingMessage = message }
            if session.guide != nil { session.guide = nil }
            if session.cursor != nil { session.cursor = nil }
            smoother.reset()
            updatePreview([])
            updateVerticalGuide(through: nil)
            return
        }
        updateAlignmentGuides(nil, cursor: nil)

        let last = session.isFinished || session.pausesRoute ? nil : session.points.last
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
                let connections = placement?.connectionPoints(catalog: catalog, cables: cables) ?? []
                (cursor, guide) = Snapping.cursor(smooth, last: last, connections: connections)
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
        updatePreview(session.previewPoints)
        updateVerticalGuide(through: guide == .vertical ? last : nil)
        updateHeightLine(at: cursor, floorY: session.floorY)
    }

    /// The floor is the lowest horizontal plane ARKit calls a floor, or else the lowest one
    /// well below the camera (tables and seats are higher).
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

    /// Cables added earlier: drawn thinner and in a calmer color than the cable being measured.
    /// The one selected in the edit mode is drawn thicker in the highlight color.
    private func render(runs: [CableRun], selected: UUID?) {
        runEntities.forEach { $0.removeFromParent() }
        runEntities.removeAll()
        for run in runs {
            let isSelected = run.id == selected
            runEntities += drawPath(run.points, color: isSelected ? Theme.arHighlight : Theme.arRun,
                                    thickness: isSelected ? 0.008 : 0.003)
        }
    }

    /// Cables the automatic mode suggests, and the start point (electrical cabinet).
    private func renderProposed(routes: [[SIMD3<Float>]], start: SIMD3<Float>?) {
        proposedEntities.forEach { $0.removeFromParent() }
        proposedEntities.removeAll()
        for route in routes {
            proposedEntities += drawPath(route, color: Theme.arProposed, thickness: 0.004)
        }
        if let start {
            let marker = ModelEntity(mesh: .generateBox(size: 0.04, cornerRadius: 0.006),
                                     materials: [UnlitMaterial(color: Theme.arStart)])
            marker.position = start
            root.addChild(marker)
            proposedEntities.append(marker)
        }
    }

    private func drawPath(_ points: [SIMD3<Float>], color: UIColor, thickness: Float) -> [Entity] {
        var entities: [Entity] = []
        for point in points {
            let dot = ModelEntity(mesh: .generateSphere(radius: thickness * 1.6), materials: [UnlitMaterial(color: color)])
            dot.position = point
            root.addChild(dot)
            entities.append(dot)
        }
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = Self.makeSegmentEntity(color: color, thickness: thickness)
            Self.place(segment, from: a, to: b)
            root.addChild(segment)
            entities.append(segment)
        }
        return entities
    }

    /// A colored plate over the fixture selected in the edit mode.
    private func updateHighlight() {
        guard let placement, let id = placement.selectedId,
              let item = placement.placed.first(where: { $0.id == id }) else {
            if highlight.isEnabled { highlight.isEnabled = false }
            return
        }
        let size = FixtureGeometry.size(frameMM: catalog[item.fixtureId]?.frameMM)
        let depth = Float(catalog[item.fixtureId]?.depthMM ?? 12) / 1000
        highlight.setTransformMatrix(item.transform, relativeTo: root)
        if let plate = highlight.children.first {
            plate.scale = [size.x + 0.02, size.y + 0.02, depth + 0.004]
            plate.position = [0, 0, depth / 2]
        }
        highlight.isEnabled = true
    }

    /// The live cable: the segments between `points` (2 or 3 points), hidden when empty.
    private func updatePreview(_ points: [SIMD3<Float>]) {
        let segments = Array(zip(points, points.dropFirst()))
        for (i, entity) in preview.enumerated() {
            guard i < segments.count, simd_distance(segments[i].0, segments[i].1) > 0.005 else {
                entity.isEnabled = false
                continue
            }
            Self.place(entity, from: segments[i].0, to: segments[i].1)
            entity.isEnabled = true
        }
    }

    /// Dotted line from the floor up to `point`.
    private func updateHeightLine(at point: SIMD3<Float>?, floorY: Float?) {
        guard let point, let floorY, point.y > floorY + 0.05 else {
            heightLine.set(from: nil, to: nil)
            return
        }
        heightLine.set(from: [point.x, floorY, point.z], to: point)
    }

    /// Dotted lines that show what the part preview lines up with: from the other part to the
    /// preview (and a bit past it), or a short line at the standard height.
    private func updateAlignmentGuides(_ alignment: Alignment?, cursor: simd_float4x4?) {
        guard let alignment, let cursor, !alignment.isEmpty else {
            levelGuide.set(from: nil, to: nil)
            aboveGuide.set(from: nil, to: nil)
            return
        }
        let here = cursor.translation
        if let level = alignment.level {
            let d = here - level
            levelGuide.set(from: level - d * 0.3, to: here + d * 0.3)
        } else if alignment.standardHeight != nil {
            let right = cursor.axisX * 0.6
            levelGuide.set(from: here - right, to: here + right)
        } else {
            levelGuide.set(from: nil, to: nil)
        }
        if let vertical = alignment.vertical {
            let d = here - vertical
            aboveGuide.set(from: vertical - d * 0.3, to: here + d * 0.3)
        } else {
            aboveGuide.set(from: nil, to: nil)
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

/// A dotted line between two points, made of a fixed pool of small boxes.
@MainActor
private final class DashedLine {
    let entity = Entity()
    private var dashes: [ModelEntity] = []
    private let dash: Float = 0.02
    private let period: Float = 0.04
    private static let maxLength: Float = 4

    init(color: UIColor, thickness: Float = 0.003) {
        for _ in 0..<Int(Self.maxLength / period) {
            let piece = ModelEntity(mesh: .generateBox(width: thickness, height: dash, depth: thickness),
                                    materials: [UnlitMaterial(color: color)])
            piece.isEnabled = false
            entity.addChild(piece)
            dashes.append(piece)
        }
        entity.isEnabled = false
    }

    /// Shows dashes from `a` to `b`; hides the line when either is nil or they are too close.
    func set(from a: SIMD3<Float>?, to b: SIMD3<Float>?) {
        guard let a, let b, simd_distance(a, b) > 0.03 else {
            if entity.isEnabled { entity.isEnabled = false }
            return
        }
        let d = b - a
        let length = simd_length(d)
        entity.position = a
        entity.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
        entity.isEnabled = true
        for (i, piece) in dashes.enumerated() {
            let bottom = Float(i) * period
            let visible = bottom + dash <= length
            if piece.isEnabled != visible { piece.isEnabled = visible }
            if visible { piece.position = [0, bottom + dash / 2, 0] }
        }
    }
}

/// Target for the tap gesture on the ARView (gesture recognizers need an Objective-C target).
private final class TapHandler: NSObject {
    private let onTap: @MainActor (CGPoint) -> Void

    init(onTap: @escaping @MainActor (CGPoint) -> Void) {
        self.onTap = onTap
    }

    @MainActor @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        onTap(recognizer.location(in: recognizer.view))
    }
}

import ARKit
import Combine
import os
import QuartzCore
import RealityKit
import UIKit

/// Puts switch and socket models on walls and keeps them there.
///
/// Every placement is an `ARAnchor` named "fixture:<fixture id>", so ARKit keeps it fixed
/// in the room while the user walks around. The room itself is saved as an `ARWorldMap` at
/// `mapURL` (one per room); the placements are saved in the room's JSON. When a room is
/// opened, ARKit first recognises it (relocalizes) and then everything is put back.
@MainActor
final class ARFixturePlacer {
    static let anchorPrefix = "fixture:"
    private static let logger = Logger(subsystem: "Kabelmeter", category: "Placement")
    /// Save the world map at most this often while placements change.
    private static let saveInterval: CFTimeInterval = 3

    private let arView: ARView
    private let fixtures: [String: Fixture]
    private weak var placement: PlacementSession?

    /// Placed id -> anchor and the entity that follows it.
    private var placedAnchors: [UUID: (anchor: ARAnchor, entity: AnchorEntity)] = [:]
    /// Where the room is saved; nil means nothing is saved (e.g. before a room is open).
    var mapURL: URL?
    private var templates: [String: Entity] = [:]
    private let ghostRoot = AnchorEntity(world: .zero)
    private var ghost: Entity?
    private var ghostModel: String?
    private var smoother = CursorSmoother(window: 4, jumpDistance: 0.15)
    /// Last wall pose and when it was found: kept briefly when ARKit loses the wall for a
    /// moment, so the "+" button does not flicker off (same idea as the measuring cursor).
    private var lastPose: (pose: simd_float4x4, time: CFTimeInterval)?
    private static let holdDuration: CFTimeInterval = 0.5
    private var subscriptions: Set<AnyCancellable> = []
    private var isDirty = false
    private var lastSave: CFTimeInterval = 0

    init(arView: ARView, fixtures: [Fixture]) {
        self.arView = arView
        self.fixtures = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        arView.scene.addAnchor(ghostRoot)
    }

    /// Call before running the session.
    func prepare(placement: PlacementSession) {
        self.placement = placement
        placement.$placed
            .sink { [weak self] placed in self?.sync(placed) }
            .store(in: &subscriptions)
        // Save before the app goes to the background, so a quick close does not lose placements.
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.flush() }
            .store(in: &subscriptions)
    }

    /// Called by ARMeasureProvider about 15 times per second.
    /// `connections` are the points a new part may click onto (cable points and edges of
    /// placed parts); `floorY` is needed for the standard-height guide.
    func tick(frame: ARFrame?, connections: [ConnectionPoint], floorY: Float?) {
        guard let placement else { return }
        let tracking = frame?.camera.trackingState
        var isNormal = false
        if case .normal = tracking { isNormal = true }

        // Relocalized: coordinates now match the saved room.
        if placement.isRestoring, isNormal { placement.isRestoring = false }
        saveIfNeeded(frame)

        var pose: simd_float4x4?
        var guide: MeasureGuide?
        var alignment = Alignment.none
        if placement.isActive, !placement.isRestoring, isNormal, let frame {
            let fixture = placement.selectedFixtureId.flatMap { fixtures[$0] }
            let now = CACurrentMediaTime()
            var raw: simd_float4x4?
            if let found = surfacePose(camera: frame.camera, ceiling: fixture?.isCeiling == true) {
                lastPose = (found, now)
                raw = found
            } else if let last = lastPose, now - last.time < Self.holdDuration {
                raw = last.pose
            } else {
                smoother.reset()
            }
            if let raw {
                let size = FixtureGeometry.size(frameMM: fixture?.frameMM)
                var (snapped, kind) = ConnectionSnapping.snapFixture(pose: raw, size: size, to: connections)
                if kind == nil {
                    // Not clicked onto something: line up with the other parts on this wall.
                    (snapped, alignment) = AlignmentSnapping.align(
                        pose: snapped, others: placement.placed.map(\.transform), floorY: floorY,
                        standardHeight: fixture.flatMap { FixtureGeometry.standardHeight(product: $0.product) })
                }
                pose = snapped
                guide = kind.map(MeasureGuide.init)
            }
        } else {
            smoother.reset()
            lastPose = nil
        }
        if placement.cursor != pose { placement.cursor = pose }
        if placement.guide != guide { placement.guide = guide }
        if placement.alignment != alignment { placement.alignment = alignment }
        updateGhost(pose: pose, fixtureId: placement.isActive ? placement.selectedFixtureId : nil)
    }

    /// Saves now (best effort), e.g. before the session pauses.
    func flush() {
        saveIfNeeded(nil, force: true)
    }

    /// Forgets every placement in the scene (the saved room stays), before opening a room.
    func removeAll() {
        for item in placedAnchors.values {
            arView.session.remove(anchor: item.anchor)
            item.entity.removeFromParent()
        }
        placedAnchors.removeAll()
        isDirty = false
    }

    /// Something in the room changed (e.g. a cable): save the room map again soon.
    func markDirty() {
        isDirty = true
    }

    // MARK: Anchors

    private func sync(_ placed: [PlacedFixture]) {
        let wanted = Set(placed.map(\.id))
        for (id, item) in placedAnchors where !wanted.contains(id) {
            arView.session.remove(anchor: item.anchor)
            item.entity.removeFromParent()
            placedAnchors[id] = nil
            isDirty = true
        }
        for item in placed where placedAnchors[item.id] == nil {
            let anchor = ARAnchor(name: Self.anchorPrefix + item.fixtureId, transform: item.transform)
            arView.session.add(anchor: anchor)
            attach(anchor, id: item.id, fixtureId: item.fixtureId)
            isDirty = true
        }
    }

    private func attach(_ anchor: ARAnchor, id: UUID, fixtureId: String) {
        let entity = AnchorEntity(anchor: anchor)
        arView.scene.addAnchor(entity)
        placedAnchors[id] = (anchor, entity)
        guard let fixture = fixtures[fixtureId] else { return }
        withModel(fixture) { [weak entity] model in
            entity?.addChild(model)
        }
    }

    // MARK: Cursor and preview

    /// Pose on the wall (or, for a ceiling light, the ceiling) under the crosshair, or nil when none is hit.
    ///
    /// Without LiDAR (iPhone 15 and other non-Pro models) a plain wall has few feature points,
    /// so an estimated plane with `.vertical` alignment rarely comes back. Tries, in order:
    /// 1. a detected wall within its bounds;
    /// 2. an estimated surface of any alignment, kept only when its normal makes it a wall
    ///    (WallPose rejects floors and ceilings). For a ceiling light the same steps run on horizontal
    ///    surfaces above the camera (CeilingPose);
    /// 3. a detected wall extended infinitely (a wall ARKit saw only partly; past a corner
    ///    this can hit the extension of another wall).
    private func surfacePose(camera: ARCamera, ceiling: Bool) -> simd_float4x4? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let cam = camera.transform.columns.3
        let cameraPosition = SIMD3(cam.x, cam.y, cam.z)
        let forward = -SIMD3(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
        // A ceiling is a horizontal surface above the camera; a wall a vertical one.
        let alignment: ARRaycastQuery.TargetAlignment = ceiling ? .horizontal : .vertical
        let queries: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneGeometry, alignment),
            (.estimatedPlane, .any),
            (.existingPlaneInfinite, alignment),
        ]
        func pose(position: SIMD3<Float>, normal: SIMD3<Float>) -> simd_float4x4? {
            ceiling
                ? CeilingPose.make(position: position, normal: normal, cameraPosition: cameraPosition,
                                   cameraForward: forward)
                : WallPose.make(position: position, normal: normal, cameraPosition: cameraPosition)
        }
        for (target, alignment) in queries {
            for hit in arView.raycast(from: center, allowing: target, alignment: alignment) {
                let t = hit.worldTransform
                // The y axis of a plane (and of a raycast hit on it) is the surface normal.
                let normalSource = (hit.anchor as? ARPlaneAnchor)?.transform ?? t
                let normal = SIMD3(normalSource.columns.1.x, normalSource.columns.1.y, normalSource.columns.1.z)
                let position = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                guard pose(position: position, normal: normal) != nil else { continue }
                return pose(position: smoother.add(position), normal: normal)
            }
        }
        smoother.reset()
        return nil
    }

    /// A see-through copy of the selected model at the crosshair.
    private func updateGhost(pose: simd_float4x4?, fixtureId: String?) {
        let fixture = fixtureId.flatMap { fixtures[$0] }
        let model = fixture?.model
        if model != ghostModel {
            ghost?.removeFromParent()
            ghost = nil
            ghostModel = model
            if let fixture, let model {
                withModel(fixture) { [weak self] entity in
                    guard let self, self.ghostModel == model else { return }
                    entity.components.set(OpacityComponent(opacity: 0.55))
                    entity.isEnabled = false
                    self.ghostRoot.addChild(entity)
                    self.ghost = entity
                }
            }
        }
        guard let ghost else { return }
        if let pose {
            ghost.setTransformMatrix(pose, relativeTo: nil)
            ghost.isEnabled = true
        } else {
            ghost.isEnabled = false
        }
    }

    // MARK: Models

    /// Hands a fresh copy of the fixture's model to `use`, loading it once.
    private func withModel(_ fixture: Fixture, _ use: @escaping @MainActor (Entity) -> Void) {
        if let template = templates[fixture.model] {
            use(template.clone(recursive: true))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let template = await self.loadTemplate(fixture)
            use(template.clone(recursive: true))
        }
    }

    /// Loads a bundled model, or a plain frame when that fails, so a placement is never invisible.
    private func loadTemplate(_ fixture: Fixture) async -> Entity {
        if let template = templates[fixture.model] { return template }
        let template: Entity
        // Switches, sockets and lights all have a bundled model (lights: light-<sku>.usdz from
        // scripts/generate_light_models.py).
        if let url = Bundle.main.url(forResource: fixture.model, withExtension: "usdz")
            ?? Bundle.main.url(forResource: fixture.model, withExtension: "usdz", subdirectory: "Models"),
           let loaded = try? await Entity(contentsOf: url) {
            template = Self.unanchored(loaded)
        } else if fixture.shape != nil {
            // A light without a model file: a stand-in shape of about the right size.
            Self.logger.error("Light model \(fixture.model, privacy: .public) missing; showing a stand-in shape")
            template = Self.lightModel(for: fixture)
        } else {
            Self.logger.error("Model \(fixture.model, privacy: .public) could not be loaded; showing a plain frame")
            template = Self.fallbackModel(for: fixture)
        }
        templates[fixture.model] = template
        return template
    }

    /// The model files carry `preliminary:anchoring` (vertical plane) so AR Quick Look snaps them
    /// to a wall. RealityKit turns that into an AnchoringComponent, and an anchor nested inside our
    /// own AnchorEntity is not drawn where we put it. So: move the content into a plain entity and
    /// drop any anchoring on the way.
    private static func unanchored(_ loaded: Entity) -> Entity {
        let container = Entity()
        container.transform = loaded.transform
        for child in Array(loaded.children) {
            container.addChild(child)
        }
        removeAnchoring(container)
        return container
    }

    private static func removeAnchoring(_ entity: Entity) {
        entity.components.remove(AnchoringComponent.self)
        for child in entity.children {
            removeAnchoring(child)
        }
    }

    /// A stand-in for a light, back on the wall or ceiling (z = 0), +Z out of the surface.
    /// Not the real product: the shape and size are indicative.
    private static func lightModel(for fixture: Fixture) -> Entity {
        let frame = fixture.frameMM ?? [100, 100]
        let width = Float(frame.first ?? 100) / 1000
        let height = Float(frame.last ?? 100) / 1000
        let depth = Float(fixture.depthMM ?? 50) / 1000
        let dark = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), roughness: 0.5, isMetallic: false)
        let white = SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)
        let glow = UnlitMaterial(color: UIColor(red: 1, green: 0.93, blue: 0.75, alpha: 1))
        let container = Entity()
        // A cylinder's axis is +Y; turn it to +Z so it stands out of the surface.
        let alongZ = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        switch fixture.shape {
        case "cylinder":
            let plate = ModelEntity(mesh: .generateBox(width: width * 0.7, height: height * 0.5, depth: 0.02),
                                    materials: [dark])
            plate.position.z = 0.01
            let body = ModelEntity(mesh: .generateCylinder(height: height, radius: width / 2), materials: [dark])
            body.position.z = max(depth - width / 2, 0.02)
            container.addChild(plate)
            container.addChild(body)
        case "disc":
            let disc = ModelEntity(mesh: .generateCylinder(height: depth, radius: width / 2), materials: [white])
            disc.orientation = alongZ
            disc.position.z = depth / 2
            container.addChild(disc)
        case "recessed":
            let ring = ModelEntity(mesh: .generateCylinder(height: depth, radius: width / 2), materials: [white])
            ring.orientation = alongZ
            ring.position.z = depth / 2
            let lens = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: width * 0.32), materials: [glow])
            lens.orientation = alongZ
            lens.position.z = depth + 0.001
            container.addChild(ring)
            container.addChild(lens)
        case "surface":
            let body = ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth, cornerRadius: depth / 2),
                                   materials: [white])
            body.position.z = depth / 2
            container.addChild(body)
        default:
            let body = ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth, cornerRadius: 0.006),
                                   materials: [dark])
            body.position.z = depth / 2
            container.addChild(body)
        }
        return container
    }

    /// A white plate of the right size, back on the wall (z = 0), like the real models.
    private static func fallbackModel(for fixture: Fixture) -> Entity {
        let frame = fixture.frameMM ?? [80, 80]
        let width = Float(frame.first ?? 80) / 1000
        let height = Float(frame.last ?? 80) / 1000
        let depth = Float(fixture.depthMM ?? 12) / 1000
        let plate = ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth, cornerRadius: 0.004),
                                materials: [SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)])
        plate.position.z = depth / 2
        let container = Entity()
        container.addChild(plate)
        return container
    }

    // MARK: Saving the room

    private func saveIfNeeded(_ frame: ARFrame?, force: Bool = false) {
        // Never while recognising a room: that would overwrite it with an unrelated new map.
        guard isDirty, let mapURL, placement?.isRestoring != true else { return }
        let now = CACurrentMediaTime()
        if !force {
            guard now - lastSave >= Self.saveInterval,
                  let status = frame?.worldMappingStatus, status == .mapped || status == .extending else { return }
        }
        lastSave = now
        isDirty = false
        Self.saveWorldMap(of: arView.session, to: mapURL)
    }

    /// Nonisolated so the completion handler (called on an ARKit queue) is not tied to the main actor.
    private nonisolated static func saveWorldMap(of session: ARSession, to url: URL) {
        session.getCurrentWorldMap { map, _ in
            guard let map,
                  let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) else {
                return
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func loadMap(at url: URL) -> ARWorldMap? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }
}

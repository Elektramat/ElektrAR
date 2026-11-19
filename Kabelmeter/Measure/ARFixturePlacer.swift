import ARKit
import Combine
import os
import QuartzCore
import RealityKit
import UIKit

/// Puts switch and socket models on walls and keeps them there.
///
/// Every placement is an `ARAnchor` named "fixture:<fixture id>", so ARKit keeps it fixed
/// in the room while the user walks around. The anchors are saved with an `ARWorldMap` in
/// the app's Documents folder; on the next start ARKit recognises the room (relocalizes)
/// and the anchors, and so the models, come back at the same spot.
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
    /// ARAnchor identifiers we already handle (ours and restored ones).
    private var knownAnchorIds: Set<UUID> = []
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

    /// Call before running the session: adds the saved room to `config` if there is one.
    func prepare(_ config: ARWorldTrackingConfiguration, placement: PlacementSession) {
        self.placement = placement
        if let map = Self.loadSavedMap(),
           map.anchors.contains(where: { $0.name?.hasPrefix(Self.anchorPrefix) == true }) {
            config.initialWorldMap = map
            placement.isRestoring = true
        }
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
    func tick(frame: ARFrame?) {
        guard let placement else { return }
        let tracking = frame?.camera.trackingState
        var isNormal = false
        if case .normal = tracking { isNormal = true }

        // Relocalized: the saved anchors are now at the right spot in this session.
        if placement.isRestoring, isNormal { placement.isRestoring = false }
        if !placement.isRestoring, let frame { restoreAnchors(from: frame) }
        saveIfNeeded(frame)

        var pose: simd_float4x4?
        if placement.isActive, !placement.isRestoring, isNormal, let frame {
            let now = CACurrentMediaTime()
            if let found = wallPose(camera: frame.camera) {
                lastPose = (found, now)
                pose = found
            } else if let last = lastPose, now - last.time < Self.holdDuration {
                pose = last.pose
            } else {
                smoother.reset()
            }
        } else {
            smoother.reset()
            lastPose = nil
        }
        if placement.cursor != pose { placement.cursor = pose }
        updateGhost(pose: pose, fixtureId: placement.isActive ? placement.selectedFixtureId : nil)
    }

    /// Saves now (best effort), e.g. before the session pauses.
    func flush() {
        saveIfNeeded(nil, force: true)
    }

    /// Forgets every placement and the saved room, for a new room or a tracking reset.
    func removeAll() {
        for item in placedAnchors.values { item.entity.removeFromParent() }
        placedAnchors.removeAll()
        knownAnchorIds.removeAll()
        isDirty = false
        Self.deleteSavedMap()
    }

    // MARK: Anchors

    private func sync(_ placed: [PlacedFixture]) {
        let hadAny = !placedAnchors.isEmpty
        let wanted = Set(placed.map(\.id))
        for (id, item) in placedAnchors where !wanted.contains(id) {
            arView.session.remove(anchor: item.anchor)
            item.entity.removeFromParent()
            placedAnchors[id] = nil
            isDirty = true
        }
        for item in placed where placedAnchors[item.id] == nil {
            let anchor = ARAnchor(name: Self.anchorPrefix + item.fixtureId, transform: item.transform)
            knownAnchorIds.insert(anchor.identifier)
            arView.session.add(anchor: anchor)
            attach(anchor, id: item.id, fixtureId: item.fixtureId)
            isDirty = true
        }
        if placedAnchors.isEmpty {
            // Only forget the saved room when the user removed the last placement,
            // not on the first (empty) value while a saved room is being restored.
            if hadAny { Self.deleteSavedMap() }
            isDirty = false
        }
    }

    /// Picks up anchors that ARKit brought back from the saved world map.
    private func restoreAnchors(from frame: ARFrame) {
        guard let placement else { return }
        for anchor in frame.anchors where !knownAnchorIds.contains(anchor.identifier) {
            guard let name = anchor.name, name.hasPrefix(Self.anchorPrefix) else { continue }
            knownAnchorIds.insert(anchor.identifier)
            let fixtureId = String(name.dropFirst(Self.anchorPrefix.count))
            attach(anchor, id: anchor.identifier, fixtureId: fixtureId)
            placement.restore(PlacedFixture(id: anchor.identifier, fixtureId: fixtureId, transform: anchor.transform))
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

    /// Pose on the wall under the crosshair, or nil when no wall is hit.
    ///
    /// Without LiDAR (iPhone 15 and other non-Pro models) a plain wall has few feature points,
    /// so an estimated plane with `.vertical` alignment rarely comes back. Tries, in order:
    /// 1. a detected wall within its bounds;
    /// 2. an estimated surface of any alignment, kept only when its normal makes it a wall
    ///    (WallPose rejects floors and ceilings);
    /// 3. a detected wall extended infinitely (a wall ARKit saw only partly; past a corner
    ///    this can hit the extension of another wall).
    private func wallPose(camera: ARCamera) -> simd_float4x4? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let cam = camera.transform.columns.3
        let cameraPosition = SIMD3(cam.x, cam.y, cam.z)
        let queries: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneGeometry, .vertical),
            (.estimatedPlane, .any),
            (.existingPlaneInfinite, .vertical),
        ]
        for (target, alignment) in queries {
            for hit in arView.raycast(from: center, allowing: target, alignment: alignment) {
                let t = hit.worldTransform
                // The y axis of a plane (and of a raycast hit on it) is the surface normal.
                let normalSource = (hit.anchor as? ARPlaneAnchor)?.transform ?? t
                let normal = SIMD3(normalSource.columns.1.x, normalSource.columns.1.y, normalSource.columns.1.z)
                let position = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                guard WallPose.make(position: position, normal: normal, cameraPosition: cameraPosition) != nil else {
                    continue
                }
                return WallPose.make(position: smoother.add(position), normal: normal, cameraPosition: cameraPosition)
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
        if let url = Bundle.main.url(forResource: fixture.model, withExtension: "usdz")
            ?? Bundle.main.url(forResource: fixture.model, withExtension: "usdz", subdirectory: "Models"),
           let loaded = try? await Entity(contentsOf: url) {
            template = Self.unanchored(loaded)
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

    private static var mapURL: URL {
        URL.documentsDirectory.appending(path: "placements.worldmap")
    }

    private func saveIfNeeded(_ frame: ARFrame?, force: Bool = false) {
        guard isDirty, !placedAnchors.isEmpty else { return }
        let now = CACurrentMediaTime()
        if !force {
            guard now - lastSave >= Self.saveInterval,
                  let status = frame?.worldMappingStatus, status == .mapped || status == .extending else { return }
        }
        lastSave = now
        isDirty = false
        Self.saveWorldMap(of: arView.session, to: Self.mapURL)
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

    private static func loadSavedMap() -> ARWorldMap? {
        guard let data = try? Data(contentsOf: mapURL) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    private static func deleteSavedMap() {
        try? FileManager.default.removeItem(at: mapURL)
    }
}

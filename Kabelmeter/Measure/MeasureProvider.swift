import Foundation

/// Source of world positions for measuring and placing. The provider writes the crosshair
/// position and tracking messages into the sessions, and draws points and placed fixtures.
/// `ARMeasureProvider` is the real one; `SimulatedMeasureProvider` fakes it for the
/// Simulator, which has no camera.
@MainActor
protocol MeasureProvider: AnyObject {
    func start(session: MeasureSession, placement: PlacementSession)
    func stop()
}

enum TrackingText {
    static let moveSlowly = "Beweeg de telefoon langzaam"
    static let aimAtSurface = "Richt op een muur of vloer"
    static let moveSideways = "Richt op een muur of vloer en beweeg zijwaarts"
    static let tooDark = "Te weinig licht"
    static let aimAtWall = "Richt op een muur"
    static let aimAtCeiling = "Richt op het plafond"
    static let relocalizing = "Richt op de plek van de vorige keer om de schakelaars terug te zetten"
    static let unavailable = "AR werkt niet op dit toestel."
}

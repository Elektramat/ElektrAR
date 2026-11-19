import Foundation

/// Source of world positions for measuring. The provider writes the crosshair position
/// and tracking messages into the session, and draws the session's points.
/// `ARMeasureProvider` is the real one; `SimulatedMeasureProvider` fakes it for the
/// Simulator and for Demo-modus on stage.
@MainActor
protocol MeasureProvider: AnyObject {
    func start(session: MeasureSession)
    func stop()
}

enum TrackingText {
    static let moveSlowly = "Beweeg de telefoon langzaam"
    static let aimAtSurface = "Richt op een muur of vloer"
    static let moveSideways = "Richt op een muur of vloer en beweeg zijwaarts"
    static let tooDark = "Te weinig licht"
    static let unavailable = "AR werkt niet op dit toestel. Zet Demo-modus aan."
}

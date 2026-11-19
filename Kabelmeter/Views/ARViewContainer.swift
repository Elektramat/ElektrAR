import RealityKit
import SwiftUI

/// Wraps the ARView of an ARMeasureProvider. The provider lives as the coordinator,
/// so it is created once and stopped when the view goes away.
struct ARViewContainer: UIViewRepresentable {
    let session: MeasureSession
    let placement: PlacementSession
    let fixtures: [Fixture]

    func makeCoordinator() -> ARMeasureProvider { ARMeasureProvider(fixtures: fixtures) }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.start(session: session, placement: placement)
        return context.coordinator.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: ARMeasureProvider) {
        coordinator.stop()
    }
}

/// Stand-in for the camera in the Simulator and in Demo-modus: draws the wall,
/// the measured points and the crosshair position from the simulated provider.
struct SimulatedMeasureView: View {
    @ObservedObject var session: MeasureSession
    @ObservedObject var placement: PlacementSession
    let fixtures: [Fixture]
    @StateObject private var provider = SimulatedMeasureProvider()

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 5.4, geo.size.height / 3.4)
            let origin = CGPoint(x: (geo.size.width - 4.6 * scale) / 2, y: geo.size.height * 0.62)
            let map = { (p: SIMD3<Float>) in
                CGPoint(x: origin.x + CGFloat(p.x) * scale, y: origin.y - CGFloat(p.y - 1.4) * scale)
            }

            ZStack {
                Theme.simulatedBackground
                Canvas { context, _ in
                    // Wall outline
                    let wall = CGRect(x: map([0, 2.6, 0]).x - 20, y: map([0, 2.6, 0]).y,
                                      width: 4.6 * scale + 40, height: 2.6 * scale)
                    context.fill(Path(wall), with: .color(Theme.simulatedWall))

                    // Cables added earlier
                    for run in session.runs {
                        var runPath = Path()
                        for (i, p) in run.points.enumerated() {
                            i == 0 ? runPath.move(to: map(p)) : runPath.addLine(to: map(p))
                        }
                        context.stroke(runPath, with: .color(Theme.run), lineWidth: 3)
                    }

                    // Dotted height line from the crosshair (or the switch preview) to the floor.
                    let heightPoint = placement.isActive ? placement.cursor?.translation : session.cursor
                    if let heightPoint, let floorY = session.floorY, heightPoint.y > floorY + 0.05 {
                        var line = Path()
                        line.move(to: map(heightPoint))
                        line.addLine(to: map(SIMD3(heightPoint.x, floorY, heightPoint.z)))
                        context.stroke(line, with: .color(Theme.height),
                                       style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }

                    // Confirmed segments
                    var path = Path()
                    for (i, p) in session.points.enumerated() {
                        i == 0 ? path.move(to: map(p)) : path.addLine(to: map(p))
                    }
                    context.stroke(path, with: .color(Theme.accent), lineWidth: 4)

                    // Live preview segment
                    if !session.isFinished, let last = session.points.last, let cursor = session.cursor {
                        var preview = Path()
                        preview.move(to: map(last))
                        preview.addLine(to: map(cursor))
                        context.stroke(preview, with: .color(Theme.accent.opacity(0.6)),
                                       style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    }

                    for p in session.points {
                        let c = map(p)
                        context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                                     with: .color(.white))
                    }

                    // Placed switches and sockets, drawn larger than real size so they stay visible.
                    for item in placement.placed {
                        drawFixture(item.fixtureId, at: map(item.position), size: 0.12 * scale, in: &context)
                    }
                    if placement.isActive, let pose = placement.cursor, let id = placement.selectedFixtureId {
                        var ghost = context
                        ghost.opacity = 0.5
                        drawFixture(id, at: map(SIMD3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)),
                                    size: 0.12 * scale, in: &ghost)
                    }
                }

                // The crosshair of MeasureScreen sits in the middle; here we show where it "points".
                if let cursor = session.cursor {
                    let c = map(cursor)
                    Circle().strokeBorder(.white, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .position(c)
                }

                Text("Demo-modus: gesimuleerde punten")
                    .font(Theme.labelFont)
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.30)
            }
        }
        .onAppear {
            provider.catalog = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            provider.start(session: session, placement: placement)
        }
        .onDisappear { provider.stop() }
    }

    private func drawFixture(_ fixtureId: String, at center: CGPoint, size: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.fill(Path(roundedRect: rect, cornerRadius: size * 0.15), with: .color(.white))
        context.stroke(Path(roundedRect: rect, cornerRadius: size * 0.15), with: .color(.gray), lineWidth: 1)
        let inner = rect.insetBy(dx: size * 0.22, dy: size * 0.22)
        if fixtures.first(where: { $0.id == fixtureId })?.product == "stopcontact" {
            context.stroke(Path(ellipseIn: inner), with: .color(.gray), lineWidth: 1.5)
        } else {
            context.stroke(Path(roundedRect: inner, cornerRadius: 2), with: .color(.gray), lineWidth: 1.5)
        }
    }
}

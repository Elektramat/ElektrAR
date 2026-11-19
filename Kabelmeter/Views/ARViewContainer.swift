import RealityKit
import SwiftUI

/// Wraps the ARView of an ARMeasureProvider. The provider lives as the coordinator,
/// so it is created once and stopped when the view goes away.
struct ARViewContainer: UIViewRepresentable {
    let session: MeasureSession
    let placement: PlacementSession
    let fixtures: [Fixture]
    /// Where the open room is saved.
    let mapURL: URL?

    func makeCoordinator() -> ARMeasureProvider { ARMeasureProvider(fixtures: fixtures, mapURL: mapURL) }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.start(session: session, placement: placement)
        return context.coordinator.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: ARMeasureProvider) {
        coordinator.stop()
    }
}

/// Stand-in for the camera in the Simulator: draws the wall,
/// the measured points and the crosshair position from the simulated provider.
struct SimulatedMeasureView: View {
    @ObservedObject var session: MeasureSession
    @ObservedObject var placement: PlacementSession
    let fixtures: [Fixture]
    @StateObject private var provider = SimulatedMeasureProvider()

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 5.6, geo.size.height / 5.0)
            let origin = CGPoint(x: (geo.size.width - 4.6 * scale) / 2, y: geo.size.height * 0.46)
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

                    // Cables added earlier (the selected one thicker), and suggested ones.
                    let polyline = { (points: [SIMD3<Float>]) -> Path in
                        var path = Path()
                        for (i, p) in points.enumerated() {
                            i == 0 ? path.move(to: map(p)) : path.addLine(to: map(p))
                        }
                        return path
                    }
                    for run in session.runs {
                        let selected = run.id == session.selectedRunId
                        context.stroke(polyline(run.points), with: .color(selected ? Theme.highlight : Theme.run),
                                       lineWidth: selected ? 6 : 3)
                    }
                    for route in session.proposedRoutes {
                        context.stroke(polyline(route), with: .color(Theme.proposed),
                                       style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    }
                    if let start = session.startPoint {
                        let c = map(start)
                        context.fill(Path(roundedRect: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18),
                                          cornerRadius: 3), with: .color(Theme.start))
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

                    // Live preview (with a corner when drawing with right angles)
                    let preview = session.previewPoints
                    if preview.count >= 2 {
                        context.stroke(polyline(preview), with: .color(Theme.run),
                                       style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    }

                    // What the part preview lines up with
                    if placement.isActive, let pose = placement.cursor {
                        let here = pose.translation
                        let dashed = StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        if let level = placement.alignment.level {
                            let d = here - level
                            context.stroke(polyline([level - d * 0.3, here + d * 0.3]), with: .color(Theme.align), style: dashed)
                        } else if placement.alignment.standardHeight != nil {
                            context.stroke(polyline([here - [0.6, 0, 0], here + [0.6, 0, 0]]), with: .color(Theme.align), style: dashed)
                        }
                        if let vertical = placement.alignment.vertical {
                            let d = here - vertical
                            context.stroke(polyline([vertical - d * 0.3, here + d * 0.3]), with: .color(Theme.align), style: dashed)
                        }
                    }

                    for p in session.points {
                        let c = map(p)
                        context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                                     with: .color(.white))
                    }

                    // Placed switches and sockets, drawn larger than real size so they stay visible.
                    for item in placement.placed {
                        if item.id == placement.selectedId {
                            let c = map(item.position), r = 0.12 * scale * 0.75
                            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                         with: .color(Theme.highlight.opacity(0.6)))
                        }
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
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let screen = { (p: SIMD3<Float>) -> SIMD2<Double>? in
                    let c = map(p)
                    return SIMD2(Double(c.x), Double(c.y))
                }
                session.tapped = TapHit.target(at: SIMD2(Double(value.location.x), Double(value.location.y)),
                                               fixtures: placement.placed.map { ($0.id, screen($0.position)) },
                                               cables: session.runs.map { ($0.id, $0.points.map(screen)) })
            })
        }
        .onAppear {
            provider.catalog = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            provider.start(session: session, placement: placement)
        }
        .onDisappear { provider.stop() }
    }

    private func drawFixture(_ fixtureId: String, at center: CGPoint, size: CGFloat, in context: inout GraphicsContext) {
        if fixtures.first(where: { $0.id == fixtureId })?.isConsumerUnit == true {
            // The generic consumer unit: 220 x 360 mm, a dark box with a row of breakers.
            let box = CGRect(x: center.x - size * 0.9, y: center.y - size * 1.5, width: size * 1.8, height: size * 3)
            context.fill(Path(roundedRect: box, cornerRadius: size * 0.1), with: .color(Color(white: 0.3)))
            context.stroke(Path(roundedRect: box, cornerRadius: size * 0.1), with: .color(.white), lineWidth: 1.5)
            for i in 0..<4 {
                let breaker = CGRect(x: box.minX + size * (0.2 + 0.38 * CGFloat(i)), y: center.y + size * 0.2,
                                     width: size * 0.28, height: size * 0.6)
                context.fill(Path(breaker), with: .color(i == 3 ? .red : .white))
            }
            return
        }
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.fill(Path(roundedRect: rect, cornerRadius: size * 0.15), with: .color(.white))
        context.stroke(Path(roundedRect: rect, cornerRadius: size * 0.15), with: .color(.gray), lineWidth: 1)
        let inner = rect.insetBy(dx: size * 0.22, dy: size * 0.22)
        if fixtures.first(where: { $0.id == fixtureId })?.isLight == true {
            context.fill(Path(ellipseIn: inner), with: .color(Theme.lightDot))
        } else if fixtures.first(where: { $0.id == fixtureId })?.product == "stopcontact" {
            context.stroke(Path(ellipseIn: inner), with: .color(.gray), lineWidth: 1.5)
        } else {
            context.stroke(Path(roundedRect: inner, cornerRadius: 2), with: .color(.gray), lineWidth: 1.5)
        }
    }
}

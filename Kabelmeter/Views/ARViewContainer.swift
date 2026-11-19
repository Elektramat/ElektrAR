import RealityKit
import SwiftUI

/// Wraps the ARView of an ARMeasureProvider. The provider lives as the coordinator,
/// so it is created once and stopped when the view goes away.
struct ARViewContainer: UIViewRepresentable {
    let session: MeasureSession

    func makeCoordinator() -> ARMeasureProvider { ARMeasureProvider() }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.start(session: session)
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

                    // Confirmed segments (as legs along the wall in that mode)
                    var path = Path()
                    for (a, b) in zip(session.points, session.points.dropFirst()) {
                        for (from, to) in MeasureMath.legs(a, b, mode: session.mode) {
                            path.move(to: map(from))
                            path.addLine(to: map(to))
                        }
                    }
                    context.stroke(path, with: .color(Theme.accent), lineWidth: 4)

                    // Live preview segment
                    if !session.isFinished, let last = session.points.last, let cursor = session.cursor {
                        var preview = Path()
                        for (from, to) in MeasureMath.legs(last, cursor, mode: session.mode) {
                            preview.move(to: map(from))
                            preview.addLine(to: map(to))
                        }
                        context.stroke(preview, with: .color(Theme.accent.opacity(0.6)),
                                       style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    }

                    for p in session.points {
                        let c = map(p)
                        context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                                     with: .color(.white))
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
        .onAppear { provider.start(session: session) }
        .onDisappear { provider.stop() }
    }
}

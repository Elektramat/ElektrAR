import Combine
import Foundation
import simd

/// Fake measuring for the Simulator and for Demo-modus. The crosshair walks along a
/// route on a wall (x = horizontal, y = height, in meters), so the length and price
/// change live, just like on a device.
@MainActor
final class SimulatedMeasureProvider: ObservableObject, MeasureProvider {
    /// Route from the electrical cabinet up, along the ceiling line, and down to a switch.
    static let route: [SIMD3<Float>] = [
        [0.0, 0.9, 0], [0.0, 2.3, 0], [3.2, 2.3, 0], [3.2, 1.05, 0], [4.6, 1.05, 0],
    ]
    private static let speed: Float = 0.35 // meters per second

    private weak var session: MeasureSession?
    private var timer: AnyCancellable?
    private var travelled: Float = 0

    func start(session: MeasureSession) {
        self.session = session
        session.trackingMessage = nil
        timer = Timer.publish(every: 1.0 / 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.cancel()
    }

    private func tick() {
        travelled += Self.speed / 15
        let total = Float(MeasureMath.pathLength(Self.route))
        if travelled > total { travelled = 0 }
        session?.cursor = Self.position(at: travelled)
    }

    static func position(at distance: Float) -> SIMD3<Float> {
        var left = distance
        for (a, b) in zip(route, route.dropFirst()) {
            let length = simd_distance(a, b)
            if left <= length { return a + (b - a) * (left / length) }
            left -= length
        }
        return route.last ?? .zero
    }
}

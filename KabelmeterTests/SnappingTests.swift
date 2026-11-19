import XCTest
import simd
@testable import KabelmeterCore

final class SnappingTests: XCTestCase {
    private let last = SIMD3<Float>(1, 0.5, -2)

    func testNearlyVerticalSnapsToVertical() {
        let (p, guide) = Snapping.snap([1.05, 1.5, -2], from: last) // 5 cm off over 1 m ≈ 3°
        XCTAssertEqual(guide, .vertical)
        XCTAssertEqual(p, [1, 1.5, -2])
    }

    func testNearlyLevelSnapsToLevel() {
        let (p, guide) = Snapping.snap([3, 0.55, -2], from: last) // 5 cm over 2 m
        XCTAssertEqual(guide, .level)
        XCTAssertEqual(p, [3, 0.5, -2])
    }

    func testDiagonalIsNotSnapped() {
        let point = SIMD3<Float>(2, 1.5, -2)
        let (p, guide) = Snapping.snap(point, from: last)
        XCTAssertNil(guide)
        XCTAssertEqual(p, point)
    }

    func testTinySegmentIsNotSnapped() {
        let (_, guide) = Snapping.snap([1.001, 0.51, -2], from: last)
        XCTAssertNil(guide)
    }

    func testVerticalGuideFindsHeightWithoutWallHit() {
        // Camera 2 m in front of the line at 1.5 m height, aiming at 2.0 m on the line.
        let camera = SIMD3<Float>(1, 1.5, 0)
        let target = SIMD3<Float>(1, 2.0, -2)
        let p = Snapping.pointOnVerticalGuide(rayOrigin: camera, rayDirection: target - camera, through: last)
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.y, 2.0, accuracy: 1e-4)
        XCTAssertEqual(p!.x, 1, accuracy: 1e-5)
        XCTAssertEqual(p!.z, -2, accuracy: 1e-5)
    }

    func testVerticalGuideIgnoresAimFarFromLine() {
        let camera = SIMD3<Float>(1, 1.5, 0)
        let p = Snapping.pointOnVerticalGuide(rayOrigin: camera, rayDirection: [1, 0, -1], through: last)
        XCTAssertNil(p)
    }

    func testVerticalGuideIgnoresLineBehindCamera() {
        let camera = SIMD3<Float>(1, 1.5, -4) // line is behind
        let p = Snapping.pointOnVerticalGuide(rayOrigin: camera, rayDirection: [0, 0, -1], through: last)
        XCTAssertNil(p)
    }

    func testVerticalGuideLookingAlongLineReturnsNil() {
        let p = Snapping.pointOnVerticalGuide(rayOrigin: [1, 3, -2], rayDirection: [0, -1, 0], through: last)
        XCTAssertNil(p)
    }

    func testSmootherAveragesJitter() {
        var s = CursorSmoother(window: 4)
        _ = s.add([0, 0, 0])
        _ = s.add([0.01, 0, 0])
        _ = s.add([-0.01, 0, 0])
        let p = s.add([0, 0.01, 0])
        XCTAssertEqual(simd_length(p), 0.0025, accuracy: 1e-4)
    }

    func testSmootherFollowsJumpImmediately() {
        var s = CursorSmoother()
        _ = s.add([0, 0, 0])
        _ = s.add([0, 0, 0])
        XCTAssertEqual(s.add([1, 0, 0]), [1, 0, 0])
    }
}

final class VerticalGuideTests: XCTestCase {
    func testExactHeightFromRayWithoutAngleLimit() {
        // Aim 5° beside the line: limited guide rejects it, unlimited returns the closest point.
        let camera = SIMD3<Float>(0, 1.5, 2)
        let dir = SIMD3<Float>(sin(5 * .pi / 180), 0, -cos(5 * .pi / 180))
        XCTAssertNil(Snapping.pointOnVerticalGuide(rayOrigin: camera, rayDirection: dir, through: [0, 0, 0]))
        let p = Snapping.pointOnVerticalGuide(rayOrigin: camera, rayDirection: dir, through: [0, 0, 0], maxAngle: nil)
        XCTAssertEqual(p?.y ?? -1, 1.5, accuracy: 1e-4)
    }
}

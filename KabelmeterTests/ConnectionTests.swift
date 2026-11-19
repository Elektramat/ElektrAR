import XCTest
import simd
@testable import KabelmeterCore

/// A fixture on the x/y wall facing +z (identity rotation) at `position`.
private func fixturePose(_ position: SIMD3<Float>) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(position, 1)
    return m
}

private let size = SIMD2<Float>(0.08, 0.08)

final class ConnectionSnappingTests: XCTestCase {
    func testFourAnchorsOnTheFrameEdges() {
        let anchors = FixtureGeometry.anchors(transform: fixturePose([1, 1, 0]), size: size)
        let bySide = Dictionary(uniqueKeysWithValues: anchors.map { ($0.side, $0.position) })
        XCTAssertEqual(bySide[.top], [1, 1.04, 0])
        XCTAssertEqual(bySide[.bottom], [1, 0.96, 0])
        XCTAssertEqual(bySide[.left], [0.96, 1, 0])
        XCTAssertEqual(bySide[.right], [1.04, 1, 0])
    }

    func testDefaultSizeWhenCatalogHasNone() {
        XCTAssertEqual(FixtureGeometry.size(frameMM: nil), [0.08, 0.08])
        XCTAssertEqual(FixtureGeometry.size(frameMM: [81, 71]), [0.081, 0.071])
    }

    func testMeasureCursorSnapsToFixtureEdge() {
        let points = ConnectionSnapping.points(fixtures: [(fixturePose([1, 1, 0]), size)], cables: [])
        let (cursor, guide) = Snapping.cursor([1.02, 1.07, 0], last: nil, connections: points)
        XCTAssertEqual(cursor, [1, 1.04, 0])
        XCTAssertEqual(guide, .fixture)
    }

    func testMeasureCursorSnapsToEarlierCable() {
        let points = ConnectionSnapping.points(fixtures: [], cables: [[[0, 0.9, 0], [0, 2.3, 0]]])
        let (cursor, guide) = Snapping.cursor([0.03, 2.28, 0], last: nil, connections: points)
        XCTAssertEqual(cursor, [0, 2.3, 0])
        XCTAssertEqual(guide, .cable)
    }

    func testConnectionBeatsLevelSnapping() {
        let points = ConnectionSnapping.points(fixtures: [(fixturePose([2, 1, 0]), size)], cables: [])
        // Level with the last point, but close to the left edge of the switch.
        let (cursor, guide) = Snapping.cursor([1.93, 1.01, 0], last: [0, 1, 0], connections: points)
        XCTAssertEqual(cursor, [1.96, 1, 0])
        XCTAssertEqual(guide, .fixture)
    }

    func testFarAwayFallsBackToAxisSnapping() {
        let points = ConnectionSnapping.points(fixtures: [(fixturePose([2, 1, 0]), size)], cables: [])
        let (cursor, guide) = Snapping.cursor([1, 1.02, 0], last: [0, 1, 0], connections: points)
        XCTAssertEqual(cursor, [1, 1, 0])
        XCTAssertEqual(guide, .level)
    }

    func testFixtureLinesUpNextToAnotherFixture() {
        let other = fixturePose([1, 1, 0])
        let points = ConnectionSnapping.points(fixtures: [(other, size)], cables: [])
        // Aimed a bit to the right of and slightly above the placed switch.
        let (snapped, kind) = ConnectionSnapping.snapFixture(pose: fixturePose([1.09, 1.02, 0.001]), size: size, to: points)
        XCTAssertEqual(kind, .fixture)
        XCTAssertLessThan(simd_distance(snapped.translation, [1.08, 1, 0]), 1e-5)
    }

    func testFixtureDoesNotSnapEdgeOnSameEdge() {
        // The new switch's right edge is near the placed switch's right edge: no side-by-side match.
        let points = ConnectionSnapping.points(fixtures: [(fixturePose([1, 1, 0]), size)], cables: [])
        let (_, kind) = ConnectionSnapping.snapFixture(pose: fixturePose([1.0, 1.0, 0]), size: size, to: points)
        XCTAssertNil(kind)
    }

    func testFixtureSnapsBottomEdgeToCableEnd() {
        let points = ConnectionSnapping.points(fixtures: [], cables: [[[0, 2.3, 0], [0, 1.0, 0]]])
        let (snapped, kind) = ConnectionSnapping.snapFixture(pose: fixturePose([0.02, 1.06, 0]), size: size, to: points)
        XCTAssertEqual(kind, .cable)
        XCTAssertLessThan(simd_distance(snapped.translation, [0, 1.04, 0]), 1e-5)
    }

    func testFixtureOnOtherWallDoesNotLineUp() {
        // Other fixture on a wall facing +x.
        var other = matrix_identity_float4x4
        other.columns.0 = [0, 0, -1, 0]
        other.columns.2 = [1, 0, 0, 0]
        other.columns.3 = [0, 1, 0.1, 1]
        let points = ConnectionSnapping.points(fixtures: [(other, size)], cables: [])
        let (_, kind) = ConnectionSnapping.snapFixture(pose: fixturePose([0.06, 1, 0]), size: size, to: points)
        XCTAssertNil(kind)
    }
}

final class FloorHeightTests: XCTestCase {
    func testHeightAboveFloor() {
        XCTAssertEqual(FloorHeight.height(of: [0, 1.05, 0], floorY: 0) ?? 0, 1.05, accuracy: 1e-6)
        XCTAssertEqual(FloorHeight.height(of: [0, 0.3, 0], floorY: -0.75) ?? 0, 1.05, accuracy: 1e-6)
        XCTAssertNil(FloorHeight.height(of: [0, 1, 0], floorY: nil))
        XCTAssertNil(FloorHeight.height(of: nil, floorY: 0))
    }

    func testPrefersPlanesClassifiedAsFloor() {
        let planes: [(y: Float, isFloor: Bool)] = [(-1.4, false), (-1.2, true), (-0.6, false)]
        XCTAssertEqual(FloorHeight.floorY(planes: planes, cameraY: 0), -1.2)
    }

    func testWithoutClassificationIgnoresTables() {
        let planes: [(y: Float, isFloor: Bool)] = [(-0.6, false), (-1.4, false)]
        XCTAssertEqual(FloorHeight.floorY(planes: planes, cameraY: 0), -1.4)
        XCTAssertNil(FloorHeight.floorY(planes: [(-0.6, false)], cameraY: 0))
    }

    func testHeightFormat() {
        XCTAssertEqual(Format.height(1.05), "1,05 m")
    }
}

@MainActor
final class CableRunTests: XCTestCase {
    func testCompleteRunKeepsItAndStartsANewOne() {
        let session = MeasureSession()
        session.cursor = [0, 0, 0]
        session.addPoint()
        session.cursor = [0, 2, 0]
        session.addPoint()
        session.completeRun(cableId: "c1")
        XCTAssertEqual(session.runs.count, 1)
        XCTAssertEqual(session.runs.first?.length ?? 0, 2, accuracy: 1e-6)
        XCTAssertTrue(session.points.isEmpty)
        session.reset()
        XCTAssertEqual(session.runs.count, 1, "reset only clears the current cable")
        session.resetAll()
        XCTAssertTrue(session.runs.isEmpty)
    }

    func testSinglePointIsNotARun() {
        let session = MeasureSession()
        session.cursor = [0, 0, 0]
        session.addPoint()
        session.completeRun(cableId: "c1")
        XCTAssertTrue(session.runs.isEmpty)
        XCTAssertEqual(session.points.count, 1)
    }
}

final class AlignmentTests: XCTestCase {
    private let size = SIMD2<Float>(0.08, 0.08)

    func testLevelWithAnotherPartWithinTolerance() {
        let other = fixturePose([1, 1.05, 0])
        let (pose, alignment) = AlignmentSnapping.align(pose: fixturePose([2, 1.08, 0]), others: [other],
                                                        floorY: nil, standardHeight: nil)
        XCTAssertEqual(alignment.level, [1, 1.05, 0])
        XCTAssertNil(alignment.vertical)
        XCTAssertLessThan(simd_distance(pose.translation, [2, 1.05, 0]), 1e-5)
        XCTAssertEqual(alignment.label, "Waterpas met ander onderdeel")
    }

    func testHalfAMeterHigherIsNotPulledDown() {
        let (pose, alignment) = AlignmentSnapping.align(pose: fixturePose([2, 1.55, 0]), others: [fixturePose([1, 1.05, 0])],
                                                        floorY: nil, standardHeight: nil)
        XCTAssertTrue(alignment.isEmpty)
        XCTAssertEqual(pose.translation, [2, 1.55, 0])
    }

    func testStraightAboveAnotherPart() {
        let (pose, alignment) = AlignmentSnapping.align(pose: fixturePose([1.02, 0.3, 0]), others: [fixturePose([1, 1.05, 0])],
                                                        floorY: nil, standardHeight: nil)
        XCTAssertEqual(alignment.vertical, [1, 1.05, 0])
        XCTAssertLessThan(simd_distance(pose.translation, [1, 0.3, 0]), 1e-5)
    }

    func testStandardHeightWhenNothingToAlignWith() {
        let (pose, alignment) = AlignmentSnapping.align(pose: fixturePose([1, 0.32, 0]), others: [],
                                                        floorY: 0, standardHeight: 0.30)
        XCTAssertEqual(alignment.standardHeight, 0.30)
        XCTAssertLessThan(simd_distance(pose.translation, [1, 0.30, 0]), 1e-5)
        XCTAssertEqual(alignment.label, "Standaardhoogte 0,30 m")
    }

    func testOtherWallDoesNotAlign() {
        var other = matrix_identity_float4x4
        other.columns.0 = [0, 0, -1, 0]
        other.columns.2 = [1, 0, 0, 0]
        other.columns.3 = [0, 1.05, 1, 1]
        let (_, alignment) = AlignmentSnapping.align(pose: fixturePose([2, 1.06, 0]), others: [other],
                                                     floorY: nil, standardHeight: nil)
        XCTAssertTrue(alignment.isEmpty)
    }

    func testStandardHeights() {
        XCTAssertEqual(FixtureGeometry.standardHeight(product: "schakelaar"), 1.05)
        XCTAssertEqual(FixtureGeometry.standardHeight(product: "stopcontact"), 0.30)
        XCTAssertNil(FixtureGeometry.standardHeight(product: "x"))
    }
}

@MainActor
final class RightAngleTests: XCTestCase {
    func testPreviewGoesUpThenSideways() {
        let s = MeasureSession()
        s.cursor = [0, 1, 0]
        s.addPoint()
        s.cursor = [2, 2.25, 0]
        XCTAssertEqual(s.previewPoints, [[0, 1, 0], [0, 2.25, 0], [2, 2.25, 0]])
        XCTAssertEqual(s.totalLength, 3.25, accuracy: 1e-6)
    }

    func testPlusAddsCornerAndUndoRemovesBoth() {
        let s = MeasureSession()
        s.cursor = [0, 1, 0]; s.addPoint()
        s.cursor = [2, 2.25, 0]; s.addPoint()
        XCTAssertEqual(s.points.count, 3)
        s.undo()
        XCTAssertEqual(s.points, [[0, 1, 0]])
    }

    func testStraightLineWithoutRightAngles() {
        let s = MeasureSession()
        s.rightAngles = false
        s.cursor = [0, 1, 0]; s.addPoint()
        s.cursor = [2, 2.25, 0]
        XCTAssertEqual(s.previewPoints.count, 2)
        s.addPoint()
        XCTAssertEqual(s.points.count, 2)
    }

    func testAlignedCursorNeedsNoCorner() {
        XCTAssertEqual(MeasureSession.route(from: [0, 1, 0], to: [0, 2, 0], rightAngles: true).count, 2)
        XCTAssertEqual(MeasureSession.route(from: [0, 1, 0], to: [3, 1, 0], rightAngles: true).count, 2)
    }
}

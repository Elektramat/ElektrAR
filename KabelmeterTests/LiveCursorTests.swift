import Combine
import XCTest
import simd
@testable import KabelmeterCore

/// The room screen observes the sessions. A moving crosshair (about 15 updates a second) must
/// not make the sessions announce a change; only the cursor appearing or disappearing may.
@MainActor
final class LiveCursorTests: XCTestCase {
    func testMovingCursorDoesNotRedrawTheScreen() {
        let session = MeasureSession()
        var sessionChanges = 0
        var liveChanges = 0
        let a = session.objectWillChange.sink { _ in sessionChanges += 1 }
        let b = session.live.objectWillChange.sink { _ in liveChanges += 1 }
        session.cursor = [0, 1, 0]                        // appears: one session change
        for i in 1...45 { session.cursor = [Float(i) * 0.01, 1, 0] }  // 3 seconds of moving
        session.cursor = nil                              // disappears: one session change
        XCTAssertEqual(sessionChanges, 2)
        XCTAssertEqual(liveChanges, 47)
        XCTAssertFalse(session.hasCursor)
        _ = (a, b)
    }

    func testPlacementCursorWorksTheSameWay() {
        let placement = PlacementSession()
        var changes = 0
        let a = placement.objectWillChange.sink { _ in changes += 1 }
        placement.isActive = true
        changes = 0
        for i in 0..<30 {
            var pose = matrix_identity_float4x4
            pose.columns.3 = SIMD4(Float(i) * 0.01, 1, 0, 1)
            placement.cursor = pose
        }
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(placement.canPlace)
        _ = a
    }

    func testDerivedValuesStillFollowTheCursor() {
        let session = MeasureSession()
        session.cursor = [0, 0, 0]
        XCTAssertTrue(session.addPoint())
        session.cursor = [3, 0, 0]
        XCTAssertGreaterThan(session.totalLength, 0)
        XCTAssertTrue(session.canAddPoint)
    }
}

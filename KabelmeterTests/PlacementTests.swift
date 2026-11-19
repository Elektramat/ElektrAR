import XCTest
import simd
@testable import KabelmeterCore

final class WallPoseTests: XCTestCase {
    private func column(_ m: simd_float4x4, _ i: Int) -> SIMD3<Float> {
        let c = [m.columns.0, m.columns.1, m.columns.2, m.columns.3][i]
        return SIMD3(c.x, c.y, c.z)
    }

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(a, b), 1e-4, "\(a) != \(b)", file: file, line: line)
    }

    func testFacesTheCameraAndStaysUpright() throws {
        // Wall in the x/y plane, normal reported away from the camera.
        let m = try XCTUnwrap(WallPose.make(position: [1, 1.05, 0], normal: [0, 0, -1],
                                            cameraPosition: [1, 1.4, 2], offset: 0))
        assertClose(column(m, 2), [0, 0, 1])
        assertClose(column(m, 1), [0, 1, 0])
        assertClose(column(m, 0), [1, 0, 0])
        assertClose(column(m, 3), [1, 1.05, 0])
    }

    func testOffsetMovesOutOfTheWall() throws {
        let m = try XCTUnwrap(WallPose.make(position: [0, 1, 0], normal: [1, 0, 0],
                                            cameraPosition: [3, 1, 0], offset: 0.001))
        assertClose(column(m, 3), [0.001, 1, 0])
        assertClose(column(m, 1), [0, 1, 0])
    }

    func testSlightlyTiltedNormalKeepsYUpAlongTheWall() throws {
        let m = try XCTUnwrap(WallPose.make(position: .zero, normal: simd_normalize([0, 0.1, 1]),
                                            cameraPosition: [0, 0, 2]))
        let x = column(m, 0), y = column(m, 1), z = column(m, 2)
        XCTAssertEqual(simd_dot(x, y), 0, accuracy: 1e-5)
        XCTAssertEqual(simd_dot(y, z), 0, accuracy: 1e-5)
        XCTAssertGreaterThan(y.y, 0.99)
        XCTAssertEqual(simd_length(simd_cross(x, y) - z), 0, accuracy: 1e-5) // right-handed
    }

    func testRejectsFloorsAndCeilings() {
        XCTAssertNil(WallPose.make(position: .zero, normal: [0, 1, 0], cameraPosition: [0, 1.5, 1]))
        XCTAssertNil(WallPose.make(position: [0, 2.5, 0], normal: [0, -1, 0], cameraPosition: [0, 1.5, 1]))
        XCTAssertNil(WallPose.make(position: .zero, normal: .zero, cameraPosition: [0, 0, 1]))
    }
}

@MainActor
final class PlacementSessionTests: XCTestCase {
    private let pose = matrix_identity_float4x4

    func testPlaceNeedsActiveModeAndCursor() {
        let s = PlacementSession()
        XCTAssertFalse(s.place("a"))
        s.isActive = true
        XCTAssertFalse(s.place("a"))
        s.cursor = pose
        XCTAssertTrue(s.place("a"))
        XCTAssertEqual(s.placed.map(\.fixtureId), ["a"])
    }

    func testUndoClearAndNewRoom() {
        let s = PlacementSession()
        s.isActive = true
        s.cursor = pose
        s.place("a"); s.place("b")
        s.undo()
        XCTAssertEqual(s.placed.map(\.fixtureId), ["a"])
        s.clearAll()
        XCTAssertTrue(s.placed.isEmpty)

        var requests = 0
        let sub = s.newRoomRequests.sink { requests += 1 }
        s.place("c")
        s.isRestoring = true
        s.startNewRoom()
        XCTAssertTrue(s.placed.isEmpty)
        XCTAssertFalse(s.isRestoring)
        XCTAssertEqual(requests, 1)
        sub.cancel()
    }

    func testRestoreIgnoresDuplicates() {
        let s = PlacementSession()
        let item = PlacedFixture(id: UUID(), fixtureId: "a", transform: pose)
        s.restore(item)
        s.restore(item)
        XCTAssertEqual(s.placed.count, 1)
    }

    func testTotalCountsIncompleteSeparately() throws {
        let json = #"""
        [{"id":"a","brand":"B","line":"l","colour":"wit","product":"schakelaar","productName":"x","mounting":"inbouw","model":"a","complete":true,"price":13.48,"parts":[],"note":null},
         {"id":"b","brand":"B","line":"l","colour":"wit","product":"stopcontact","productName":"x","mounting":"opbouw","model":"b","complete":false,"price":null,"parts":[],"note":null}]
        """#
        let catalog = try FixtureCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog[1].title, "Stopcontact opbouw")
        let s = PlacementSession()
        s.isActive = true
        s.cursor = pose
        s.place("a"); s.place("a"); s.place("b")
        let total = s.total(in: catalog)
        XCTAssertEqual(total.price, 26.96, accuracy: 1e-9)
        XCTAssertEqual(total.incomplete, 1)
    }

    func testBundledFixturesHaveAModelEach() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Kabelmeter/Resources")
        let fixtures = try FixtureCatalog.decode(Data(contentsOf: resources.appendingPathComponent("fixtures.json")))
        XCTAssertFalse(fixtures.isEmpty)
        for f in fixtures {
            let model = resources.appendingPathComponent("Models/\(f.model).usdz")
            XCTAssertTrue(FileManager.default.fileExists(atPath: model.path), "No model for \(f.id)")
            for part in f.parts {
                XCTAssertTrue(part.productUrl.absoluteString.hasPrefix("https://www.elektramat.nl/"))
            }
        }
    }

    func testRejectsCompleteFixtureWithoutPrice() {
        let json = #"[{"id":"a","brand":"B","line":"l","colour":"wit","product":"schakelaar","productName":"x","mounting":"inbouw","model":"a","complete":true,"price":null,"parts":[],"note":null}]"#
        XCTAssertThrowsError(try FixtureCatalog.decode(Data(json.utf8)))
    }
}

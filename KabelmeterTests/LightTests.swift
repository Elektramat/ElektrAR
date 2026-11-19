import XCTest
import simd
@testable import KabelmeterCore

final class CeilingPoseTests: XCTestCase {
    private func column(_ m: simd_float4x4, _ i: Int) -> SIMD3<Float> {
        let c = [m.columns.0, m.columns.1, m.columns.2, m.columns.3][i]
        return SIMD3(c.x, c.y, c.z)
    }

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(a, b), 1e-4, "\(a) != \(b)", file: file, line: line)
    }

    func testPointsDownAndFollowsTheCameraDirection() throws {
        let m = try XCTUnwrap(CeilingPose.make(position: [1, 2.5, 1], normal: [0, 1, 0],
                                               cameraPosition: [1, 1.5, 3], cameraForward: [0, 0.6, -0.8],
                                               offset: 0))
        assertClose(column(m, 2), [0, -1, 0])   // +Z out of the ceiling, down
        assertClose(column(m, 1), [0, 0, -1])   // +Y along the horizontal view direction
        assertClose(column(m, 3), [1, 2.5, 1])
        // Right-handed and orthonormal.
        assertClose(simd_cross(column(m, 0), column(m, 1)), column(m, 2))
    }

    func testRejectsAFloorAndATable() {
        // The floor is below the camera.
        XCTAssertNil(CeilingPose.make(position: [0, 0, 0], normal: [0, 1, 0], cameraPosition: [0, 1.5, 0],
                                      cameraForward: [0, 0, -1]))
        // A table top is only slightly above the camera when the user crouches.
        XCTAssertNil(CeilingPose.make(position: [0, 1.6, 0], normal: [0, 1, 0], cameraPosition: [0, 1.5, 0],
                                      cameraForward: [0, 0, -1]))
    }

    func testRejectsAWall() {
        XCTAssertNil(CeilingPose.make(position: [0, 2.5, -2], normal: [0, 0, 1], cameraPosition: [0, 1.5, 0],
                                      cameraForward: [0, 0, -1]))
    }

    func testLookingStraightUpStillGivesAPose() throws {
        let m = try XCTUnwrap(CeilingPose.make(position: [0, 2.5, 0], normal: [0, -1, 0],
                                               cameraPosition: [0, 1.5, 0], cameraForward: [0, 1, 0], offset: 0))
        assertClose(column(m, 2), [0, -1, 0])
        XCTAssertEqual(simd_length(column(m, 1)), 1, accuracy: 1e-4)
    }
}

final class LightCatalogTests: XCTestCase {
    private let json = #"""
    [{"id":"401328651","sku":"401328651","name":"Calex Smart Halo LED inbouwspot RGB en CCT 6.5W 340lm IP44 - dimbaar",
      "brand":"Calex","surface":"ceiling","shape":"recessed","sizeMM":[90,90,30],"price":21.34,
      "productUrl":"https://www.elektramat.nl/calex-smart-halo-led-inbouwspot-rgb-en-cct-6-5w-340lm-ip44-dimbaar-5301001000/",
      "shopProductId":1299136},
     {"id":"401328667","sku":"401328667","name":"Calex Smart Outdoor buiten wandlamp","brand":"Calex",
      "surface":"wall","shape":"box","sizeMM":[100,100,100],"price":24.45,
      "productUrl":"https://www.elektramat.nl/calex-smart-outdoor-buiten-wandlamp-5401002500/","shopProductId":1299151}]
    """#

    func testLightsBecomeOrderableFixtures() throws {
        let fixtures = try FixtureCatalog.decodeLights(Data(json.utf8))
        XCTAssertEqual(fixtures.map(\.id), ["light-401328651", "light-401328667"])
        let spot = fixtures[0]
        XCTAssertTrue(spot.isLight)
        XCTAssertTrue(spot.isCeiling)
        XCTAssertEqual(spot.title, "Inbouwspot")
        XCTAssertEqual(spot.price, 21.34)
        XCTAssertTrue(spot.complete)
        XCTAssertEqual(spot.parts.first?.shopProductId, 1299136)
        XCTAssertEqual(spot.frameMM, [90, 90])
        XCTAssertEqual(spot.depthMM, 30)
        XCTAssertFalse(fixtures[1].isCeiling)
        XCTAssertEqual(fixtures[1].title, "Wandlamp")
    }

    func testLightsDoNotClashWithSwitchIds() throws {
        let lights = try FixtureCatalog.decodeLights(Data(json.utf8))
        XCTAssertTrue(lights.allSatisfy { $0.id.hasPrefix("light-") })
    }

    @MainActor
    func testAddingALightToTheCartKeepsTheShopProductId() throws {
        let defaults = UserDefaults(suiteName: "LightCatalogTests")!
        defaults.removePersistentDomain(forName: "LightCatalogTests")
        let store = CartStore(defaults: defaults)
        let lamp = try XCTUnwrap(FixtureCatalog.decodeLights(Data(json.utf8)).first)
        let result = store.add(fixture: lamp, count: 2)
        XCTAssertEqual(result.pieces, 2)
        XCTAssertEqual(result.incompleteFixtures, 0)
        XCTAssertEqual(store.items.first?.quantity, 2)
        XCTAssertEqual(store.items.first?.shopProductId, 1299136)
        XCTAssertEqual(store.total, 42.68)
    }
}

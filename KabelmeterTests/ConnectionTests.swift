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

@MainActor
final class FixtureCartTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "FixtureCartTests-\(UUID().uuidString)")
    }

    private func part(_ sku: String, _ price: Double?) -> FixturePart {
        FixturePart(role: "x", sku: sku, description: "Onderdeel \(sku)", price: price,
                    productUrl: URL(string: "https://www.elektramat.nl/\(sku)")!)
    }

    private func fixture(_ id: String, parts: [FixturePart], complete: Bool = true) -> Fixture {
        Fixture(id: id, brand: "Busch-Jaeger", line: "future linear", colour: "studiowit", product: "schakelaar",
                productName: "Wipschakelaar", mounting: "inbouw", model: id, complete: complete,
                price: complete ? parts.compactMap(\.price).reduce(0, +) : nil, parts: parts, note: nil,
                frameMM: [80, 80], depthMM: 12)
    }

    func testAddsEachPartByElektramatCode() {
        let store = CartStore(defaults: defaults)
        let result = store.add(fixture: fixture("a", parts: [part("401", 5), part("402", 3.5)]), count: 3)
        XCTAssertEqual(result, FixtureCartResult(pieces: 6, incompleteFixtures: 0))
        XCTAssertEqual(store.items.map(\.sku), ["401", "402"])
        XCTAssertEqual(store.items.map(\.quantity), [3, 3])
        XCTAssertEqual(store.items.first?.kind, .part)
        XCTAssertEqual(store.total, 25.5)
    }

    func testSharedPartFromTwoFixturesIsOneLine() {
        let store = CartStore(defaults: defaults)
        store.add(fixture: fixture("a", parts: [part("frame", 4), part("rocker", 2)]), count: 1)
        store.add(fixture: fixture("b", parts: [part("frame", 4), part("insert", 9)]), count: 2)
        XCTAssertEqual(store.items.first { $0.sku == "frame" }?.quantity, 3)
        XCTAssertEqual(store.count, 3)
    }

    func testIncompleteFixtureSkipsPartsWithoutPrice() {
        let store = CartStore(defaults: defaults)
        let result = store.add(fixture: fixture("a", parts: [part("401", 6.16), part("402", nil)], complete: false),
                               count: 2)
        XCTAssertEqual(result, FixtureCartResult(pieces: 2, incompleteFixtures: 2))
        XCTAssertEqual(store.items.map(\.sku), ["401"])
    }

    func testCableAndPartWithSameIdStaySeparate() {
        let store = CartStore(defaults: defaults)
        let cable = Cable(id: "401", sku: "401", name: "Kabel", crossSection: "3x1,5 mm²", use: "x",
                          pricePerMeter: 1, sales: .perMeter(step: 1, minimum: 1), stock: "x", imageUrl: nil,
                          productUrl: URL(string: "https://www.elektramat.nl")!, isSample: false)
        store.add(cable: cable, meters: 10)
        store.add(fixture: fixture("a", parts: [part("401", 5)]), count: 1)
        XCTAssertEqual(store.count, 2)
    }

    func testSetQuantityAndRemoveAtZero() throws {
        let store = CartStore(defaults: defaults)
        store.add(fixture: fixture("a", parts: [part("401", 5)]), count: 1)
        let id = try XCTUnwrap(store.items.first?.id)
        store.setQuantity(4, for: id)
        XCTAssertEqual(store.items.first?.quantity, 4)
        store.setQuantity(0, for: id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testReadsCartSavedByOlderBuild() throws {
        let old = #"[{"id":"6B1E8A2C-0E57-4C1F-9C11-8E2B5C1F0A01","cableId":"c1","sku":"S1","name":"Kabel","crossSection":"3x1,5 mm²","pricePerMeter":0.99,"meters":12,"productUrl":"https://www.elektramat.nl","isSample":false}]"#
        defaults.set(Data(old.utf8), forKey: "cart.items.v1")
        let item = try XCTUnwrap(CartStore(defaults: defaults).items.first)
        XCTAssertEqual(item.kind, .cable)
        XCTAssertEqual(item.productId, "c1")
        XCTAssertEqual(item.detail, "3x1,5 mm²")
        XCTAssertEqual(item.unitPrice, 0.99)
        XCTAssertEqual(item.quantity, 12)
    }
}

@MainActor
final class PlacementCartTests: XCTestCase {
    func testOnlyNewPlacementsAreAddedAgain() {
        let placement = PlacementSession()
        placement.isActive = true
        placement.cursor = fixturePose([0, 1, 0])
        placement.place("a")
        placement.place("a")
        placement.place("b")
        XCTAssertEqual(placement.notInCart.map(\.fixtureId), ["a", "b"])
        XCTAssertEqual(placement.notInCart.map(\.count), [2, 1])
        placement.markAllInCart()
        XCTAssertTrue(placement.notInCart.isEmpty)
        placement.place("a")
        XCTAssertEqual(placement.notInCart.map(\.count), [1])
    }
}

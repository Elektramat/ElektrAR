import XCTest
import simd
@testable import KabelmeterCore

final class BillTests: XCTestCase {
    private let url = URL(string: "https://www.elektramat.nl/x")!

    private func cable(_ id: String, price: Double, sales: SalesUnit = .perMeter(step: 1, minimum: 1)) -> Cable {
        Cable(id: id, sku: "sku-\(id)", name: "Kabel \(id)", crossSection: "3x1,5 mm²", use: "x", pricePerMeter: price,
              sales: sales, stock: "x", imageUrl: nil, productUrl: url, isSample: false)
    }

    private func fixture(_ id: String, parts: [(String, Double?)], complete: Bool = true) -> Fixture {
        Fixture(id: id, brand: "Busch-Jaeger", line: "future linear", colour: "studiowit", product: "schakelaar",
                productName: "Wipschakelaar", mounting: "inbouw", model: id, complete: complete,
                price: complete ? parts.compactMap(\.1).reduce(0, +) : nil,
                parts: parts.map { FixturePart(role: "x", sku: $0.0, description: "Onderdeel \($0.0)", price: $0.1,
                                               productUrl: url) },
                note: nil, frameMM: [80, 80], depthMM: 12)
    }

    private func room(_ name: String, fixtures: [String] = [], runs: [(String, Double)] = []) -> Project {
        Project(id: UUID(), name: name, createdAt: Date(), updatedAt: Date(), floorY: 0, startPoint: nil,
                placements: fixtures.map { .init(id: UUID(), fixtureId: $0, transform: Project.encode(matrix_identity_float4x4)) },
                runs: runs.map { .init(id: UUID(), cableId: $0.0, points: [[0, 0, 0], [Float($0.1), 0, 0]]) },
                cabled: [])
    }

    func testAddsUpRoomsByElektramatCode() {
        let fixtures = [fixture("a", parts: [("frame", 4), ("rocker", 6)]), fixture("b", parts: [("frame", 4), ("insert", 9)])]
        let lines = Bill.lines(projects: [room("Woonkamer", fixtures: ["a", "a"]), room("Keuken", fixtures: ["b"])],
                               cables: [], fixtures: fixtures, reserve: 0)
        let frame = lines.first { $0.sku == "frame" }
        XCTAssertEqual(frame?.quantity, 3)
        XCTAssertEqual(frame?.rooms, ["Woonkamer", "Keuken"])
        XCTAssertEqual(lines.map(\.sku), ["frame", "rocker", "insert"])
        XCTAssertEqual(Bill.total(lines), 3 * 4 + 2 * 6 + 9)
    }

    func testCableIsAddedUpThenRoundedOnce() {
        // Two cables of 2,3 m with no reserve: (2,3 + 2) * 2 = 8,6 m -> 9 m, not 5 + 5 = 10 m.
        let lines = Bill.lines(projects: [room("A", runs: [("c", 2.3)]), room("B", runs: [("c", 2.3)])],
                               cables: [cable("c", price: 1.5)], fixtures: [], reserve: 0)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].quantity, 9, accuracy: 1e-9)
        XCTAssertEqual(lines[0].linePrice, 13.5)
        XCTAssertEqual(lines[0].rooms, ["A", "B"])
    }

    func testRollsAreChosenForTheTotal() {
        let lines = Bill.lines(projects: [room("A", runs: [("r", 8)])],
                               cables: [cable("r", price: 1, sales: .fixedLengths([10, 25]))], fixtures: [], reserve: 0.15)
        XCTAssertEqual(lines.first?.pieces, [25]) // 8 * 1,15 + 2 = 11,2 m
    }

    func testSkipsPartsWithoutPriceAndCountsIncomplete() {
        let fixtures = [fixture("a", parts: [("401", 6.16), ("402", nil)], complete: false)]
        let rooms = [room("A", fixtures: ["a", "a"])]
        XCTAssertEqual(Bill.lines(projects: rooms, cables: [], fixtures: fixtures, reserve: 0).map(\.sku), ["401"])
        XCTAssertEqual(Bill.incompleteFixtures(projects: rooms, fixtures: fixtures), 2)
    }

    func testEmptyRoomsGiveEmptyList() {
        XCTAssertTrue(Bill.lines(projects: [room("Leeg")], cables: [], fixtures: [], reserve: 0.15).isEmpty)
    }

    func testRollCableBecomesOneLinePerRollSizeAcrossRooms() {
        let rolls = [(100.0, 208.77), (50, 117.66), (25, 64.51)].map {
            CableRoll(lengthM: $0.0, sku: "R\(Int($0.0))", price: $0.1, productUrl: url, shopProductId: Int($0.0), stock: nil)
        }
        let snelflex = Cable(id: "S", sku: "R100", name: "Snelflex", crossSection: "3x2,5 mm²", use: "x", pricePerMeter: 2.0877,
                             sales: .fixedLengths([100, 50, 25]), stock: "x", imageUrl: nil, productUrl: url,
                             isSample: false, rolls: rolls)
        // Two rooms with 26 m each, no reserve: (26 + 2) * 2 = 56 m -> 50 + 25 (182,17) beats 100 (208,77).
        let lines = Bill.lines(projects: [room("A", runs: [("S", 26)]), room("B", runs: [("S", 26)])],
                               cables: [snelflex], fixtures: [], reserve: 0)
        XCTAssertEqual(lines.map(\.sku), ["R50", "R25"])
        XCTAssertEqual(lines.map(\.rollCount), [1, 1])
        XCTAssertEqual(lines.map(\.rollLength), [50, 25])
        XCTAssertEqual(Bill.total(lines), 182.17)
        XCTAssertEqual(lines.first?.rooms, ["A", "B"])
        // The shop gets whole rolls per product, not meters.
        let order = WebShopOrder.lines(for: lines)
        XCTAssertEqual(order.map(\.quantity), [1, 1])
        XCTAssertEqual(order.map(\.productId), [50, 25])
    }

    func testTwoRollsOfTheSameSizeAreOneShopLine() {
        let roll = CableRoll(lengthM: 100, sku: "R100", price: 208.77, productUrl: url, shopProductId: 7, stock: nil)
        let c = Cable(id: "S", sku: "R100", name: "Snelflex", crossSection: "x", use: "x", pricePerMeter: 2.0877,
                      sales: .fixedLengths([100]), stock: "x", imageUrl: nil, productUrl: url, isSample: false, rolls: [roll])
        let lines = Bill.lines(projects: [room("A", runs: [("S", 90), ("S", 90)])], cables: [c], fixtures: [], reserve: 0)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].rollCount, 2) // (90+2)*2 = 184 m -> 2 rolls
        XCTAssertEqual(WebShopOrder.lines(for: lines).map(\.quantity), [2])
        XCTAssertEqual(Bill.total(lines), 417.54)
    }
}

final class ConsumerUnitTests: XCTestCase {
    func testIsAStandInWithoutPartsOrPrice() {
        let unit = Fixture.consumerUnit
        XCTAssertTrue(unit.isConsumerUnit)
        XCTAssertFalse(unit.isLight)
        XCTAssertTrue(unit.parts.isEmpty)
        XCTAssertNil(unit.price)
        XCTAssertEqual(unit.title, "Groepenkast")
        XCTAssertEqual(FixtureGeometry.size(frameMM: unit.frameMM), [0.22, 0.36])
    }

    func testNeverEndsUpInTheCartOrCountsAsIncomplete() {
        let transform = Project.encode(matrix_identity_float4x4)
        let room = Project(id: UUID(), name: "Meterkast", createdAt: Date(), updatedAt: Date(), floorY: 0, startPoint: nil,
                           placements: [.init(id: UUID(), fixtureId: Fixture.consumerUnit.id, transform: transform)],
                           runs: [], cabled: [])
        XCTAssertTrue(Bill.lines(projects: [room], cables: [], fixtures: [.consumerUnit], reserve: 0.15).isEmpty)
        XCTAssertEqual(Bill.incompleteFixtures(projects: [room], fixtures: [.consumerUnit]), 0)
    }
}

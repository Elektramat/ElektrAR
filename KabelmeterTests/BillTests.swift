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
}

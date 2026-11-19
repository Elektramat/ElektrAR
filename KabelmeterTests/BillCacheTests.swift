import XCTest
@testable import KabelmeterCore

@MainActor
final class BillCacheTests: XCTestCase {
    private let cable = Cable(id: "c1", sku: "S1", name: "Kabel", crossSection: "3x1,5 mm²", use: "x",
                              pricePerMeter: 1.45, sales: .perMeter(step: 1, minimum: 1), stock: "x",
                              imageUrl: nil, productUrl: URL(string: "https://www.elektramat.nl/")!, isSample: false)

    private func room(floorY: Float = 0, runLength: Float = 4) -> Project {
        Project(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Shelter", createdAt: .distantPast,
                updatedAt: .distantPast, floorY: floorY, startPoint: nil, placements: [],
                runs: [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, cableId: "c1",
                             points: [[0, 0, 0], [runLength, 0, 0]])], cabled: [])
    }

    override func setUp() async throws { BillCache.reset() }

    func testSameInputsComputeOnce() {
        for _ in 0..<30 { _ = BillCache.lines(projects: [room()], cables: [cable], fixtures: [], reserve: 0.15) }
        XCTAssertEqual(BillCache.computeCount, 1)
    }

    func testFloorHeightWhileAimingDoesNotRecompute() {
        _ = BillCache.lines(projects: [room(floorY: 0)], cables: [cable], fixtures: [], reserve: 0.15)
        _ = BillCache.lines(projects: [room(floorY: -1.2)], cables: [cable], fixtures: [], reserve: 0.15)
        XCTAssertEqual(BillCache.computeCount, 1)
    }

    func testChangedRunOrReserveGivesAFreshAndCorrectBill() {
        let short = BillCache.lines(projects: [room(runLength: 4)], cables: [cable], fixtures: [], reserve: 0.15)
        let long = BillCache.lines(projects: [room(runLength: 10)], cables: [cable], fixtures: [], reserve: 0.15)
        let moreReserve = BillCache.lines(projects: [room(runLength: 10)], cables: [cable], fixtures: [], reserve: 0.3)
        XCTAssertEqual(BillCache.computeCount, 3)
        XCTAssertEqual(short, Bill.lines(projects: [room(runLength: 4)], cables: [cable], fixtures: [], reserve: 0.15))
        XCTAssertEqual(long, Bill.lines(projects: [room(runLength: 10)], cables: [cable], fixtures: [], reserve: 0.15))
        XCTAssertEqual(moreReserve, Bill.lines(projects: [room(runLength: 10)], cables: [cable], fixtures: [], reserve: 0.3))
        XCTAssertNotEqual(short, long)
    }
}

import XCTest
import simd
@testable import KabelmeterCore

private let size = SIMD2<Float>(0.08, 0.08)

/// Fixture at `position` on a wall facing `normal` (horizontal), upright.
private func fixtureTransform(_ position: SIMD3<Float>, normal: SIMD3<Float> = [0, 0, 1]) -> simd_float4x4 {
    let z = simd_normalize(normal)
    let y = SIMD3<Float>(0, 1, 0)
    let x = simd_cross(y, z)
    return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(position, 1)))
}

final class AutoRouterTests: XCTestCase {
    func testRouteGoesUpAlongAndDownOnOneWall() {
        let a = RouteNode.fixture(transform: fixtureTransform([0, 1.05, 0]), size: size)
        let b = RouteNode.fixture(transform: fixtureTransform([2, 0.3, 0]), size: size)
        let route = AutoRouter.route(from: a, to: b, floorY: 0)
        let expected: [SIMD3<Float>] = [[0, 1.09, 0], [0, 2.25, 0], [2, 2.25, 0], [2, 0.34, 0]]
        XCTAssertEqual(route.count, expected.count)
        for (p, q) in zip(route, expected) { XCTAssertLessThan(simd_distance(p, q), 1e-5) }
        XCTAssertEqual(MeasureMath.pathLength(route), 1.16 + 2 + 1.91, accuracy: 1e-4)
    }

    func testWithoutFloorUsesZoneAboveHighestPoint() {
        let a = RouteNode.point([0, 1, 0])
        let b = RouteNode.point([1, 1.2, 0])
        XCTAssertEqual(AutoRouter.route(from: a, to: b, floorY: nil)[1].y, 1.5, accuracy: 1e-5)
    }

    func testRouteGoesThroughTheCornerBetweenTwoWalls() {
        // Wall 1: z = 0 facing +z. Wall 2: x = 3 facing -x. They meet at (3, 0).
        let a = RouteNode.fixture(transform: fixtureTransform([1, 1, 0]), size: size)
        let b = RouteNode.fixture(transform: fixtureTransform([3, 1, 2], normal: [-1, 0, 0]), size: size)
        let route = AutoRouter.route(from: a, to: b, floorY: 0)
        XCTAssertEqual(route.count, 5)
        XCTAssertLessThan(simd_distance(route[2], [3, 2.25, 0]), 1e-4)
    }

    func testChainVisitsNearestFirstFromTheStart() {
        let start = RouteNode.point([0, 0.5, 0])
        let far = RouteNode.fixture(transform: fixtureTransform([4, 1, 0]), size: size)
        let near = RouteNode.fixture(transform: fixtureTransform([1, 1, 0]), size: size)
        let routes = AutoRouter.chain(start: start, nodes: [far, near], floorY: 0)
        XCTAssertEqual(routes.count, 2)
        XCTAssertEqual(routes[0].last, near.top)
        XCTAssertEqual(routes[1].last, far.top)
    }

    func testChainWithoutStartBeginsAtFirstFixture() {
        let a = RouteNode.fixture(transform: fixtureTransform([0, 1, 0]), size: size)
        XCTAssertTrue(AutoRouter.chain(start: nil, nodes: [a], floorY: 0).isEmpty)
        XCTAssertTrue(AutoRouter.chain(start: nil, nodes: [], floorY: 0).isEmpty)
    }
}

final class TapHitTests: XCTestCase {
    func testFixtureNearTapWins() {
        let f = UUID(), c = UUID()
        let hit = TapHit.target(at: [100, 100], fixtures: [(f, [110, 105])], cables: [(c, [[0, 100], [300, 100]])])
        XCTAssertEqual(hit, .fixture(f))
    }

    func testCableSegmentNearTap() {
        let c = UUID()
        XCTAssertEqual(TapHit.target(at: [150, 120], fixtures: [], cables: [(c, [[0, 100], [300, 100]])]), .cable(c))
        XCTAssertNil(TapHit.target(at: [150, 200], fixtures: [], cables: [(c, [[0, 100], [300, 100]])]))
    }

    func testIgnoresPointsBehindTheCamera() {
        let f = UUID(), c = UUID()
        XCTAssertNil(TapHit.target(at: [10, 10], fixtures: [(f, nil)], cables: [(c, [nil, [10, 10]])]))
    }
}

@MainActor
final class PlacementEditTests: XCTestCase {
    func testReplaceKeepsSpotAndCable() throws {
        let placement = PlacementSession()
        let pose = fixtureTransform([1, 1, 0])
        placement.place("a", at: pose)
        let id = try XCTUnwrap(placement.placed.first?.id)
        placement.markCabled([id])
        placement.replace(id, with: "b")
        let new = try XCTUnwrap(placement.placed.first)
        XCTAssertEqual(new.fixtureId, "b")
        XCTAssertEqual(new.transform, pose)
        XCTAssertEqual(placement.cabled, [new.id])
    }

    func testRemoveForgetsCable() throws {
        let placement = PlacementSession()
        placement.place("a", at: fixtureTransform([1, 1, 0]))
        let id = try XCTUnwrap(placement.placed.first?.id)
        placement.markCabled([id])
        placement.remove(id)
        XCTAssertTrue(placement.placed.isEmpty)
        XCTAssertTrue(placement.cabled.isEmpty)
    }
}

@MainActor
final class ProjectStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ProjectStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveLoadAndDelete() throws {
        let pose = fixtureTransform([1, 1.05, 0], normal: [-1, 0, 0])
        let placed = PlacedFixture(id: UUID(), fixtureId: "a", transform: pose)
        let run = CableRun(id: UUID(), cableId: "c", points: [[0, 1, 0], [0, 2, 0]])
        let project = Project(id: UUID(), name: "Woonkamer", createdAt: Date(), updatedAt: Date(),
                              floorY: -1.2, startPoint: Project.encode(SIMD3<Float>(0, 0.5, 0)),
                              placements: [.init(id: placed.id, fixtureId: "a", transform: Project.encode(pose))],
                              runs: [.init(id: run.id, cableId: "c", points: run.points.map(Project.encode))],
                              cabled: [placed.id])
        let store = ProjectStore(directory: directory)
        try store.save(project)

        let loaded = try XCTUnwrap(ProjectStore(directory: directory).projects.first)
        XCTAssertEqual(loaded.name, "Woonkamer")
        XCTAssertEqual(loaded.placedFixtures, [placed])
        XCTAssertEqual(loaded.cableRuns, [run])
        XCTAssertEqual(loaded.cableLength, 1, accuracy: 1e-6)
        XCTAssertEqual(loaded.cabled, [placed.id])

        store.delete(project.id)
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testNewestFirst() throws {
        let store = ProjectStore(directory: directory)
        for (name, age) in [("Oud", 100.0), ("Nieuw", 0.0)] {
            try store.save(Project(id: UUID(), name: name, createdAt: Date(), updatedAt: Date() - age,
                                   floorY: nil, startPoint: nil, placements: [], runs: [], cabled: []))
        }
        XCTAssertEqual(store.projects.map(\.name), ["Nieuw", "Oud"])
    }
}

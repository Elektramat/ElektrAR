import Foundation

/// Remembers the last few bills, so screens that redraw many times a second (the room screen
/// follows the crosshair about 15 times a second) do not compute the same bill again each
/// time. A bill only changes when the rooms, the catalog or the reserve change, and then the
/// inputs differ and the bill is computed fresh. Comparing the inputs costs microseconds.
@MainActor
enum BillCache {
    /// Only what Bill.lines reads: the room name, which fixtures, and the cable runs. Not the
    /// floor height or the exact place of a fixture, which change while aiming.
    private struct RoomKey: Equatable {
        let name: String
        let fixtureIds: [String]
        let runs: [Project.Run]

        init(_ project: Project) {
            name = project.name
            fixtureIds = project.placements.map(\.fixtureId)
            runs = project.runs
        }
    }

    private struct Entry {
        let rooms: [RoomKey]
        let cables: [Cable]
        let fixtures: [Fixture]
        let reserve: Double
        let lines: [BillLine]
    }

    /// The room screen asks for its own room and the cart button for all rooms, so keep a few.
    private static let capacity = 6
    private static var entries: [Entry] = []
    private(set) static var computeCount = 0

    static func lines(projects: [Project], cables: [Cable], fixtures: [Fixture], reserve: Double) -> [BillLine] {
        let rooms = projects.map(RoomKey.init)
        if let index = entries.firstIndex(where: {
            $0.reserve == reserve && $0.rooms == rooms && $0.cables == cables && $0.fixtures == fixtures
        }) {
            let hit = entries.remove(at: index)
            entries.append(hit)  // most recently used last
            return hit.lines
        }
        computeCount += 1
        let lines = Bill.lines(projects: projects, cables: cables, fixtures: fixtures, reserve: reserve)
        entries.append(Entry(rooms: rooms, cables: cables, fixtures: fixtures, reserve: reserve, lines: lines))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        return lines
    }

    static func reset() {
        entries.removeAll()
        computeCount = 0
    }
}

import Combine
import Foundation
import simd

/// A saved design: placed fixtures, cables and the start point of one room.
/// In AR the room itself (an ARWorldMap) is saved next to it, so the design can come back
/// at the same spot; see `ProjectStore.mapURL`.
nonisolated struct Project: Codable, Identifiable, Equatable, Sendable {
    nonisolated struct Placement: Codable, Equatable, Sendable {
        let id: UUID
        let fixtureId: String
        /// Column-major 4x4 world transform.
        let transform: [Float]
    }

    nonisolated struct Run: Codable, Equatable, Sendable {
        let id: UUID
        let cableId: String
        let points: [[Float]]
    }

    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var floorY: Float?
    var startPoint: [Float]?
    var placements: [Placement]
    var runs: [Run]
    /// Placements that already have an automatic cable, in routing order.
    var cabled: [UUID]

    var fixtureCount: Int { placements.count }
    var cableLength: Double { runs.reduce(0) { $0 + MeasureMath.pathLength($1.points.map(Self.point)) } }

    static func encode(_ m: simd_float4x4) -> [Float] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    static func transform(_ values: [Float]) -> simd_float4x4? {
        guard values.count == 16 else { return nil }
        let c = (0..<4).map { SIMD4(values[$0 * 4], values[$0 * 4 + 1], values[$0 * 4 + 2], values[$0 * 4 + 3]) }
        return simd_float4x4(columns: (c[0], c[1], c[2], c[3]))
    }

    static func encode(_ p: SIMD3<Float>) -> [Float] { [p.x, p.y, p.z] }

    static func point(_ values: [Float]) -> SIMD3<Float> {
        values.count == 3 ? SIMD3(values[0], values[1], values[2]) : .zero
    }

    var placedFixtures: [PlacedFixture] {
        placements.compactMap { p in
            Self.transform(p.transform).map { PlacedFixture(id: p.id, fixtureId: p.fixtureId, transform: $0) }
        }
    }

    var cableRuns: [CableRun] {
        runs.map { CableRun(id: $0.id, cableId: $0.cableId, points: $0.points.map(Self.point)) }
    }
}

/// Saved designs as JSON files (plus an optional world map) in Documents/Projects.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    private let directory: URL

    init(directory: URL = URL.documentsDirectory.appending(path: "Projects")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        projects = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Project.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project).write(to: jsonURL(project.id), options: .atomic)
        reload()
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: jsonURL(id))
        try? FileManager.default.removeItem(at: mapURL(id))
        reload()
    }

    func project(id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Where the AR room of a project is saved.
    func mapURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).worldmap") }

    func hasMap(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: mapURL(id).path) }

    private func jsonURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }
}

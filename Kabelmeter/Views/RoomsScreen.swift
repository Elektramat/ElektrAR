import SwiftUI

/// Start screen: the rooms (each room is one design) and the shared cart.
struct RoomsScreen: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var fixtureStore: FixtureStore
    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)
    @State private var path: [UUID] = []
    @State private var showNewRoom = false
    @State private var roomToDelete: Project?
    @AppStorage("seenIntro") private var seenIntro = false
    @State private var showIntro = false

    var body: some View {
        // First start: the intro comes before anything else, so the camera prompt
        // appears only after the user knows why it is needed.
        if seenIntro {
            rooms.fullScreenCover(isPresented: $showIntro) { IntroView { showIntro = false } }
        } else {
            IntroView { seenIntro = true }
        }
    }

    private var rooms: some View {
        NavigationStack(path: $path) {
            List {
                if projectStore.projects.isEmpty {
                    ContentUnavailableView {
                        Label("Nog geen ruimtes", systemImage: "square.split.bottomrightquarter")
                    } description: {
                        Text("Maak een ruimte, zoals de woonkamer of keuken. Daarin plaats je schakelaars en stopcontacten en trek je de kabels.")
                    }
                }
                ForEach(projectStore.projects) { room in
                    NavigationLink(value: room.id) { row(room) }
                        .swipeActions {
                            Button("Verwijder", role: .destructive) { roomToDelete = room }
                        }
                }
            }
            .navigationTitle("Mijn ruimtes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showIntro = true } label: {
                        Image(systemName: "questionmark.circle").font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Uitleg")
                }
                ToolbarItem(placement: .topBarTrailing) { CartButton() }
            }
            .safeAreaInset(edge: .bottom) {
                Button { showNewRoom = true } label: {
                    Label("Nieuwe ruimte", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
                }
                .brandProminentButton(Theme.cta)
                .buttonBorderShape(.roundedRectangle(radius: Theme.buttonCorner))
                .padding(.horizontal, Theme.spacing)
                .padding(.bottom, 4)
            }
            .navigationDestination(for: UUID.self) { id in
                RoomScreen(roomId: id)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .sheet(isPresented: $showNewRoom) {
                NewRoomSheet { room in
                    try? projectStore.save(room)
                    path.append(room.id)
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Ruimte verwijderen?", isPresented: Binding(
                get: { roomToDelete != nil }, set: { if !$0 { roomToDelete = nil } }), titleVisibility: .visible,
                presenting: roomToDelete) { room in
                Button("Verwijder \(room.name)", role: .destructive) { projectStore.delete(room.id) }
            } message: { _ in
                Text("Alles in deze ruimte verdwijnt, ook uit de winkelwagen.")
            }
        }
    }

    private func row(_ room: Project) -> some View {
        let price = Bill.total(Bill.lines(projects: [room], cables: cableStore.cables, fixtures: fixtureStore.fixtures,
                                          reserve: Double(reservePercent) / 100))
        return HStack(spacing: Theme.spacing) {
            ProjectSketch(project: room, fixtures: fixtureStore.fixtures)
                .frame(width: 72, height: 54)
                .background(Theme.simulatedBackground, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.headline)
                Text(ProjectText.summary(room)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.euro(price)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

/// Name a new room.
private struct NewRoomSheet: View {
    let onCreate: (Project) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private static let suggestions = ["Woonkamer", "Keuken", "Slaapkamer", "Badkamer", "Hal", "Zolder", "Garage"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam, bijv. Woonkamer", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(create)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { name = suggestion }
                                    .brandProminentButton(Theme.accent)
                            }
                        }
                    }
                } footer: {
                    Text("In een ruimte plaats je eerst de schakelaars en stopcontacten, daarna trek je de kabels.")
                }
            }
            .navigationTitle("Nieuwe ruimte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Maak", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        onCreate(Project(id: UUID(), name: trimmed, createdAt: now, updatedAt: now,
                         floorY: nil, startPoint: nil, placements: [], runs: [], cabled: []))
        dismiss()
    }
}

enum ProjectText {
    static func summary(_ project: Project) -> String {
        var parts: [String] = []
        let fixtures = project.fixtureCount
        if fixtures > 0 { parts.append(fixtures == 1 ? "1 onderdeel" : "\(fixtures) onderdelen") }
        if !project.runs.isEmpty { parts.append("\(Format.meters(project.cableLength)) kabel") }
        return parts.isEmpty ? "Leeg" : parts.joined(separator: " · ")
    }
}

/// 2D sketch of a design: from the front (x, height) when everything is on one wall,
/// otherwise from above (x, z).
struct ProjectSketch: View {
    let project: Project
    let fixtures: [Fixture]
    var detailed = false

    var body: some View {
        Canvas { context, size in
            let placed = project.placedFixtures
            let runs = project.cableRuns.map(\.points)
            var all = placed.map(\.position) + runs.flatMap { $0 }
            if let start = project.startPoint { all.append(Project.point(start)) }
            guard !all.isEmpty else { return }

            let zs = all.map(\.z), xs = all.map(\.x)
            let fromAbove = (zs.max()! - zs.min()!) > 0.3 && (xs.max()! - xs.min()!) > 0.3
            let flat = { (p: SIMD3<Float>) -> CGPoint in
                fromAbove ? CGPoint(x: CGFloat(p.x), y: CGFloat(p.z)) : CGPoint(x: CGFloat(p.x), y: CGFloat(-p.y))
            }
            let points = all.map(flat)
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            let pad: CGFloat = detailed ? 24 : 6
            let scale = min((size.width - 2 * pad) / max(maxX - minX, 0.5), (size.height - 2 * pad) / max(maxY - minY, 0.5))
            let offsetX = (size.width - (maxX - minX) * scale) / 2
            let offsetY = (size.height - (maxY - minY) * scale) / 2
            let map = { (p: SIMD3<Float>) -> CGPoint in
                let f = flat(p)
                return CGPoint(x: offsetX + (f.x - minX) * scale, y: offsetY + (f.y - minY) * scale)
            }

            for run in runs {
                var path = Path()
                for (i, p) in run.enumerated() { i == 0 ? path.move(to: map(p)) : path.addLine(to: map(p)) }
                context.stroke(path, with: .color(Theme.run), lineWidth: detailed ? 3 : 1.5)
            }
            if let start = project.startPoint {
                let c = map(Project.point(start)), r: CGFloat = detailed ? 8 : 4
                context.fill(Path(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.start))
            }
            let byId = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in placed {
                let c = map(item.position), r: CGFloat = detailed ? 10 : 4
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                if byId[item.fixtureId]?.isConsumerUnit == true {
                    // The consumer unit is where the cables start: same green as the start point.
                    context.fill(Path(roundedRect: rect.insetBy(dx: -r * 0.2, dy: -r * 0.5), cornerRadius: r * 0.3),
                                 with: .color(Theme.start))
                    continue
                }
                context.fill(Path(roundedRect: rect, cornerRadius: r * 0.3), with: .color(.white))
                if detailed {
                    let inner = rect.insetBy(dx: r * 0.45, dy: r * 0.45)
                    if byId[item.fixtureId]?.product == "stopcontact" {
                        context.stroke(Path(ellipseIn: inner), with: .color(.gray), lineWidth: 1.5)
                    } else {
                        context.stroke(Path(roundedRect: inner, cornerRadius: 2), with: .color(.gray), lineWidth: 1.5)
                    }
                    if !fromAbove, let floorY = project.floorY {
                        let height = Format.height(Double(item.position.y - floorY))
                        context.draw(Text(height).font(.caption2).foregroundStyle(Theme.height),
                                     at: CGPoint(x: c.x, y: c.y + r + 8))
                    }
                }
            }
        }
        .accessibilityLabel(ProjectText.summary(project))
    }
}

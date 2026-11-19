import ARKit
import AVFoundation
import Combine
import SwiftUI
import UIKit

/// One room. "Bekijken": look around and tap a part or cable for its info.
/// "Bewerken": step 1 place the parts (switches and sockets), step 2 draw the cables,
/// automatically or by hand. Everything is saved as you go; the shared cart follows along.
struct RoomScreen: View {
    enum Mode: Hashable { case view, edit }
    enum Step: Hashable { case parts, cables }
    enum CableMode: Hashable { case auto, manual }

    let roomId: UUID

    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var fixtureStore: FixtureStore
    @EnvironmentObject private var projectStore: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = MeasureSession()
    @StateObject private var placement = PlacementSession()

    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)
    @AppStorage("selectedCableId") private var storedCableId = ""
    @AppStorage("selectedFixtureId") private var storedFixtureId = ""

    @State private var mode: Mode = .view
    @State private var step: Step = .parts
    @State private var cableMode: CableMode = .auto
    @State private var chooser: ChooserPurpose?
    @State private var showCablePicker = false
    @State private var info: TapTarget?
    /// "Verplaats": the part taken off the wall; the next "+" puts it back, "Annuleer" restores it.
    @State private var moving: (fixtureId: String, oldPose: simd_float4x4)?
    @State private var toast: Toast?
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private struct Toast: Equatable {
        let text: String
        let success: Bool
    }

    private var room: Project? { projectStore.project(id: roomId) }

    /// The Simulator has no camera: it shows a drawn wall instead.
    private var useSimulated: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private var cable: Cable? { cableStore.cables.first { $0.id == storedCableId } ?? cableStore.cables.first }

    /// The part the "+" places (shown as a see-through preview on the wall).
    private var fixture: Fixture? {
        fixtureStore.fixture(id: storedFixtureId) ?? fixtureStore.fixtures.first(where: \.complete) ?? fixtureStore.fixtures.first
    }

    private var cameraBlocked: Bool {
        !useSimulated && (cameraStatus == .denied || cameraStatus == .restricted)
    }

    private var reserve: Double { Double(reservePercent) / 100 }
    private var isEditing: Bool { mode == .edit }
    private var isLoaded: Bool { placement.loadedRoomId == roomId }

    // MARK: Body

    var body: some View {
        ZStack {
            cameraLayer
                .ignoresSafeArea()

            VStack(spacing: 10) {
                header
                modePicker
                if isEditing { stepPicker }
                statusPills
                Spacer()
                if isEditing { controls }
                bottomCard
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 4)

            if let toast {
                Label(toast.text, systemImage: toast.success ? "checkmark.circle.fill" : "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(toast.success ? Theme.cta : Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .surface(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            }
        }
        .overlay { if cameraBlocked { cameraBlockedCard } }
        // Dark status bar text is unreadable on the camera image.
        .statusBarHidden()
        .onAppear(perform: load)
        .onChange(of: scenePhase) { if $1 == .active { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) } }
        .onChange(of: mode) { sync() }
        .onChange(of: step) { sync() }
        .onChange(of: cableMode) { sync() }
        .onChange(of: fixture?.id) { sync() }
        .onChange(of: session.tapped) { openTapped() }
        .onChange(of: placement.placed) { save(); refreshAutoRoutes() }
        .onChange(of: placement.cabled) { save(); refreshAutoRoutes() }
        .onChange(of: session.runs) { save() }
        .onChange(of: session.startPoint) { save(); refreshAutoRoutes() }
        .onChange(of: session.floorY) { refreshAutoRoutes() }
        .onChange(of: info) { highlight(info) }
        .sheet(item: $chooser) { purpose in
            FixtureChooserSheet(fixtures: fixtureStore.fixtures, recent: fixture, title: purpose.title) { chosen in
                choose(chosen, for: purpose)
            }
        }
        .sheet(isPresented: $showCablePicker) {
            CablePickerSheet(cables: cableStore.cables, selectedId: Binding(
                get: { cable?.id }, set: { storedCableId = $0 ?? "" }))
        }
        .sheet(item: $info) { target in
            InfoCard(target: target, placement: placement, session: session, isEditing: isEditing, reserve: reserve,
                     onDelete: { delete(target) }, onReplace: replaceInfoFixture, onMove: moveInfoFixture,
                     onEdit: { editFromInfo(target) })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var cameraLayer: some View {
        Group {
            if useSimulated {
                SimulatedMeasureView(session: session, placement: placement, fixtures: fixtureStore.fixtures)
            } else {
                ARViewContainer(session: session, placement: placement, fixtures: fixtureStore.fixtures,
                                mapURL: projectStore.mapURL(roomId))
            }
        }
        .overlay {
            if isEditing {
                Crosshair(active: step == .parts ? placement.canPlace : session.cursor != nil)
                heightLabel
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .surface(Circle())
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Terug naar ruimtes")

            Text(room?.name ?? "Ruimte")
                .font(.headline).lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .surface(Capsule())

            Spacer(minLength: 0)
            CartButton()
        }
        .padding(.top, 4)
    }

    private var modePicker: some View {
        Picker("Modus", selection: $mode) {
            Label("Bekijken", systemImage: "eye").tag(Mode.view)
            Label("Bewerken", systemImage: "pencil").tag(Mode.edit)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .sensoryFeedback(.selection, trigger: mode)
        .padding(3)
        .surface(RoundedRectangle(cornerRadius: 11))
    }

    /// Step 1 parts, step 2 cables (automatically or by hand).
    private var stepPicker: some View {
        VStack(spacing: 8) {
            Picker("Stap", selection: $step) {
                Text("1  Onderdelen").tag(Step.parts)
                Text("2  Kabels").tag(Step.cables)
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: step)
            .padding(3)
            .surface(RoundedRectangle(cornerRadius: 11))

            if step == .cables {
                Picker("Kabels", selection: $cableMode) {
                    Text("Automatisch").tag(CableMode.auto)
                    Text("Handmatig").tag(CableMode.manual)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: cableMode)
                .padding(3)
                .surface(RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    @ViewBuilder
    private var statusPills: some View {
        VStack(spacing: 6) {
            if placement.isRestoring {
                pill("Kijk rustig rond: zodra de ruimte herkend is, komt je ontwerp terug", color: Theme.warning)
                Button("Niet herkend? Toon hier") { placement.skipRestoreRequests.send() }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .surface(Capsule())
                    .buttonStyle(CardButtonStyle())
            } else if let message = session.trackingMessage {
                pill(message, color: Theme.warning)
            } else if let hint {
                pill(hint.text, color: hint.color)
            }
        }
    }

    private var hint: (text: String, color: Color)? {
        guard isEditing else { return nil }
        switch step {
        case .parts:
            if moving != nil { return ("Richt op de nieuwe plek en tik op +", Theme.highlight) }
            if let guide = placement.guide { return (guide.label, Color(Theme.Token.secondary)) }
            if let label = placement.alignment.label { return (label, Theme.align) }
            if placement.placed.isEmpty {
                return (fixture?.isCeiling == true ? "Richt op het plafond waar de lamp komt en tik op +"
                                                   : "Richt op de muur waar het onderdeel komt en tik op +", .white)
            }
            return nil
        case .cables:
            if cableMode == .auto { return (autoHint, session.proposedRoutes.isEmpty ? .white : Theme.proposed) }
            if let guide = session.guide { return (guide.label, Color(Theme.Token.secondary)) }
            if session.points.isEmpty { return ("Begin bij een onderdeel of de groepenkast: richt en tik op +", .white) }
            return ("Tik op + bij elke hoek; tik op Klaar bij het laatste onderdeel", .white)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(color)
    }

    /// Height of the crosshair (or of the middle of the part preview) above the floor.
    @ViewBuilder
    private var heightLabel: some View {
        let point = step == .parts ? placement.cursor?.translation : session.cursor
        Group {
            if let height = FloorHeight.height(of: point, floorY: session.floorY) {
                Label("\(Format.height(height)) boven de vloer", systemImage: "arrow.up.and.down")
                    .foregroundStyle(Theme.height)
            } else if point != nil {
                Label("Richt even op de vloer voor de hoogte", systemImage: "arrow.down.to.line")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .offset(y: Theme.crosshair + 8)
        .allowsHitTesting(false)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        HStack(alignment: .center, spacing: Theme.spacing) {
            switch (step, cableMode) {
            case (.parts, _):
                controlButton("Ongedaan", icon: "arrow.uturn.backward") { undoPart() }
                    .disabled(placement.placed.isEmpty || moving != nil)
                spacer
                plusButton(enabled: placement.canPlace && fixture != nil, label: "Plaats onderdeel", action: placeFixture)
                spacer
            case (.cables, .manual):
                controlButton("Ongedaan", icon: "arrow.uturn.backward") { session.undo() }
                    .disabled(session.points.isEmpty)
                controlButton("Opnieuw", icon: "xmark") { session.reset() }
                    .disabled(session.points.isEmpty)
                plusButton(enabled: session.cursor != nil, label: "Ankerpunt toevoegen", action: addAnchor)
                controlButton("Klaar", icon: "checkmark") { finishCable() }
                    .disabled(session.points.count < 2)
            case (.cables, .auto):
                controlButton("Wis start", icon: "xmark.square") { session.startPoint = nil }
                    .disabled(session.startPoint == nil)
                spacer
                plusButton(enabled: session.cursor != nil, label: "Startpunt (groepenkast) hier") {
                    session.startPoint = session.cursor
                    confirm("Startpunt gezet")
                }
                spacer
            }
        }
    }

    private var spacer: some View { Color.clear.frame(width: Theme.tapTarget, height: Theme.tapTarget) }

    private func plusButton(enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .bold))
                .frame(width: Theme.addButton, height: Theme.addButton)
                .background(enabled ? Theme.accent : Theme.secondaryButton, in: Circle())
                .foregroundStyle(Theme.onAccent)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
        }
        .buttonStyle(CardButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// White square button with a blue icon and a short title; full color also when disabled,
    /// so it never turns grey on the camera image. The title is the accessibility label too.
    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: Theme.tapTarget + 8, height: Theme.tapTarget)
            .surface(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(title)
    }

    private var cameraBlockedCard: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Theme.accent)
            Text("Geen toegang tot de camera").font(.headline)
            Text("De Kabelmeter gebruikt de camera om je ruimte te zien. Zet de camera aan in Instellingen.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Instellingen") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .brandProminentButton()
        }
        .padding(24)
        .surface(RoundedRectangle(cornerRadius: Theme.corner))
        .padding(32)
    }

    // MARK: Bottom card

    private var roomLines: [BillLine] {
        guard let room else { return [] }
        return Bill.lines(projects: [current(room)], cables: cableStore.cables, fixtures: fixtureStore.fixtures,
                          reserve: reserve)
    }

    @ViewBuilder
    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch (mode, step, cableMode) {
            case (.view, _, _):
                roomSummary
                Text(placement.placed.isEmpty && session.runs.isEmpty
                     ? "Nog leeg. Kies Bewerken om onderdelen te plaatsen."
                     : "Tik op een onderdeel of kabel voor info.")
                    .font(Theme.labelFont).foregroundStyle(.secondary)
            case (.edit, .parts, _):
                if let moving, let part = fixtureStore.fixture(id: moving.fixtureId) {
                    HStack(spacing: Theme.spacing) {
                        FixtureIcon(fixture: part, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(part.title) verplaatsen").font(.headline)
                            Text("Tik op + op de nieuwe plek").font(Theme.labelFont).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Annuleer") { cancelMove() }.buttonStyle(.bordered).tint(Theme.accent)
                    }
                } else {
                    selectionRow(icon: { if let fixture { FixtureIcon(fixture: fixture, size: 44) } },
                                 title: fixture?.title ?? "Kies een onderdeel",
                                 subtitle: fixture.map { "\($0.subtitle) · \(FixtureText.price($0))" } ?? "",
                                 warning: fixture?.complete == false) { chooser = .select }
                }
                summaryLine
            case (.edit, .cables, .manual):
                let quote = cable.flatMap { PricingCalculator.quote(for: $0, measured: session.totalLength, reserve: reserve) }
                cableRow
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deze kabel: \(Format.meters(session.totalLength))").font(Theme.lengthFont).monospacedDigit()
                        Text(session.points.isEmpty ? "\(Format.count(session.runs.count, "kabel", "kabels")) in deze ruimte"
                                                    : Format.count(session.points.count, "ankerpunt", "ankerpunten"))
                            .font(Theme.labelFont).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(quote.map { Format.euro($0.price) } ?? "–").font(Theme.priceFont).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Toggle(isOn: $session.rightAngles) {
                    Text("Rechte hoeken: eerst omhoog of omlaag, dan opzij").font(Theme.labelFont)
                }
                .tint(Theme.accent)
                .sensoryFeedback(.selection, trigger: session.rightAngles)
            case (.edit, .cables, .auto):
                cableRow
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.proposedRoutes.isEmpty ? "Nog geen kabels voorgesteld"
                             : "\(Format.count(session.proposedRoutes.count, "kabel", "kabels")) · \(Format.meters(autoLength))")
                            .font(Theme.lengthFont).monospacedDigit()
                        Text("Omhoog naar 2,25 m, langs de muur, omlaag naar elk onderdeel")
                            .font(Theme.labelFont).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button(action: addAutoRoutes) {
                    Label("Kabels toevoegen", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
                }
                .brandProminentButton(Theme.cta)
                .buttonBorderShape(.roundedRectangle(radius: Theme.buttonCorner))
                .disabled(session.proposedRoutes.isEmpty || cable == nil)
            }
        }
        .padding(Theme.barPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(RoundedRectangle(cornerRadius: Theme.corner))
    }

    /// What the "+" places or draws, with a button to change it.
    private func selectionRow<Icon: View>(@ViewBuilder icon: () -> Icon, title: String, subtitle: String,
                                          warning: Bool = false, change: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.spacing) {
            icon()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                Text(subtitle).font(Theme.labelFont).foregroundStyle(warning ? Theme.warning : .secondary).lineLimit(2)
            }
            Spacer()
            Button("Wijzig", action: change).buttonStyle(.bordered).tint(Theme.accent)
        }
    }

    private var cableRow: some View {
        selectionRow(icon: { Image(systemName: "cable.connector").font(.title).foregroundStyle(Theme.run).frame(width: 44) },
                     title: cable?.name ?? "Kies een kabel",
                     subtitle: cable.map { "\($0.crossSection) · \(Format.euro($0.pricePerMeter)) per meter" } ?? "") {
            showCablePicker = true
        }
    }

    private var summaryLine: some View {
        let cableLength = session.runs.reduce(0) { $0 + $1.length }
        return HStack {
            Text("\(Format.count(placement.placed.count, "onderdeel", "onderdelen")) · \(Format.count(session.runs.count, "kabel", "kabels")) · \(Format.meters(cableLength))")
            Spacer()
            Text(Format.euro(Bill.total(roomLines))).fontWeight(.semibold).contentTransition(.numericText())
        }
        .font(Theme.labelFont).foregroundStyle(.secondary).monospacedDigit()
    }

    private var roomSummary: some View {
        let cableLength = session.runs.reduce(0) { $0 + $1.length }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.count(placement.placed.count, "onderdeel", "onderdelen")).font(Theme.lengthFont)
                Text("\(Format.count(session.runs.count, "kabel", "kabels")) · \(Format.meters(cableLength))")
                    .font(Theme.labelFont).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.euro(Bill.total(roomLines))).font(Theme.priceFont).monospacedDigit()
                    .contentTransition(.numericText())
                Text("in deze ruimte").font(Theme.labelFont).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Loading and saving

    private func load() {
        guard let room, placement.loadedRoomId == nil else { return }
        if useSimulated {
            session.load(runs: room.cableRuns, startPoint: room.startPoint.map(Project.point), floorY: room.floorY)
            placement.load(room.placedFixtures, cabled: room.cabled, roomId: room.id)
        } else {
            placement.pendingLoad = ProjectLoad(project: room,
                                                mapURL: projectStore.hasMap(room.id) ? projectStore.mapURL(room.id) : nil)
        }
        if room.placements.isEmpty && room.runs.isEmpty { mode = .edit }
        sync()
    }

    /// The room as it is on screen now.
    private func current(_ room: Project) -> Project {
        var updated = room
        updated.floorY = session.floorY ?? room.floorY
        updated.startPoint = session.startPoint.map(Project.encode)
        updated.placements = placement.placed.map { .init(id: $0.id, fixtureId: $0.fixtureId, transform: Project.encode($0.transform)) }
        updated.runs = session.runs.map { .init(id: $0.id, cableId: $0.cableId, points: $0.points.map(Project.encode)) }
        updated.cabled = placement.cabled
        return updated
    }

    /// Saves after every change, but only once the room's content is back (not over it while loading).
    private func save() {
        guard isLoaded, let room else { return }
        var updated = current(room)
        guard updated != room else { return }
        updated.updatedAt = Date()
        try? projectStore.save(updated)
    }

    // MARK: Mode state

    private func sync() {
        placement.isActive = isEditing && step == .parts
        session.isAiming = isEditing
        session.pausesRoute = isEditing && step == .cables && cableMode == .auto
        placement.selectedFixtureId = moving?.fixtureId ?? fixture?.id
        if !(isEditing && step == .parts), moving != nil { cancelMove() }
        refreshAutoRoutes()
    }

    // MARK: Parts

    /// "+": puts the shown part on the wall under the crosshair (or the one being moved).
    private func placeFixture() {
        guard let pose = placement.cursor else { return }
        if let moving {
            placement.place(moving.fixtureId, at: pose)
            self.moving = nil
            sync()
            flash(placement.placed.last?.id)
            confirm("\(fixtureStore.fixture(id: moving.fixtureId)?.title ?? "Onderdeel") verplaatst")
        } else if let fixture {
            placement.place(fixture.id, at: pose)
            flash(placement.placed.last?.id)
            confirm("\(fixture.title) \(fixture.line) geplaatst")
        }
    }

    private func undoPart() {
        guard let last = placement.placed.last else { return }
        placement.remove(last.id)
        note("Laatste onderdeel weggehaald")
    }

    private func choose(_ chosen: Fixture, for purpose: ChooserPurpose) {
        storedFixtureId = chosen.id
        switch purpose {
        case let .replace(id):
            placement.replace(id, with: chosen.id)
            confirm("Vervangen door \(chosen.title.lowercased()) \(chosen.line)")
        case .select:
            note("\(chosen.title) \(chosen.line) gekozen: tik op + om te plaatsen")
        }
    }

    private func cancelMove() {
        guard let moving else { return }
        placement.place(moving.fixtureId, at: moving.oldPose)
        self.moving = nil
        placement.selectedFixtureId = fixture?.id
        note("Verplaatsen geannuleerd")
    }

    // MARK: Cables

    private func addAnchor() {
        guard session.addPoint() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if session.points.count == 1 { note("Beginpunt gezet: richt op de volgende hoek") }
    }

    private func finishCable() {
        guard let cable, let run = session.completeRun(cableId: cable.id) else { return }
        flashRun(run.id)
        confirm("Kabel van \(Format.meters(run.length)) toegevoegd")
    }

    /// Cables from the start point (or the last part that has a cable) past every part without one,
    /// and the parts in the order they are visited. Parts a hand-drawn cable already ends at are skipped.
    private var autoPlan: (routes: [[SIMD3<Float>]], ids: [UUID]) {
        let size = { (item: PlacedFixture) in
            FixtureGeometry.size(frameMM: self.fixtureStore.fixture(id: item.fixtureId)?.frameMM)
        }
        let ends = session.runs.flatMap { [$0.points.first, $0.points.last].compactMap { $0 } }
        let pending = placement.notCabled.filter { item in
            !FixtureGeometry.anchors(transform: item.transform, size: size(item)).contains { anchor in
                ends.contains { simd_distance($0, anchor.position) <= ConnectionSnapping.distance }
            }
        }
        let node = { (item: PlacedFixture) in RouteNode.fixture(transform: item.transform, size: size(item)) }
        let nodes = pending.map(node)
        let lastCabled = placement.cabled.last.flatMap { id in placement.placed.first { $0.id == id } }
        let start = lastCabled.map(node) ?? session.startPoint.map(RouteNode.point)
        let routes = AutoRouter.chain(start: start, nodes: nodes, floorY: session.floorY)
        let order = AutoRouter.order(start: start, nodes: nodes)
        return (routes, order.map { pending[$0].id })
    }

    private func refreshAutoRoutes() {
        let routes = isEditing && step == .cables && cableMode == .auto ? autoPlan.routes : []
        if session.proposedRoutes != routes { session.proposedRoutes = routes }
    }

    private var autoLength: Double { session.proposedRoutes.reduce(0) { $0 + MeasureMath.pathLength($1) } }

    private var autoHint: String {
        let count = session.proposedRoutes.count
        if count > 0 {
            return "\(Format.count(count, "kabel", "kabels")) voorgesteld: controleer en tik op Kabels toevoegen"
        }
        if placement.placed.isEmpty { return "Plaats eerst onderdelen bij stap 1" }
        if autoPlan.ids.isEmpty { return "Alle onderdelen hebben een kabel" }
        return "Richt op de groepenkast en tik op + als startpunt"
    }

    private func addAutoRoutes() {
        guard let cable else { return }
        let plan = autoPlan
        session.addRuns(plan.routes, cableId: cable.id)
        placement.markCabled(plan.ids)
        confirm("\(Format.count(plan.routes.count, "kabel", "kabels")) toegevoegd")
    }

    // MARK: Info card

    private func openTapped() {
        guard let tapped = session.tapped else { return }
        session.tapped = nil
        info = tapped
    }

    private func highlight(_ target: TapTarget?) {
        switch target {
        case let .fixture(id):
            placement.selectedId = id
            session.selectedRunId = nil
        case let .cable(id):
            session.selectedRunId = id
            placement.selectedId = nil
        case nil:
            placement.selectedId = nil
            session.selectedRunId = nil
        }
    }

    private func delete(_ target: TapTarget) {
        switch target {
        case let .fixture(id): placement.remove(id)
        case let .cable(id): session.removeRun(id)
        }
        info = nil
        confirm("Verwijderd")
    }

    private func replaceInfoFixture() {
        guard case let .fixture(id) = info else { return }
        info = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350)) // let the info sheet close first
            chooser = .replace(id)
        }
    }

    private func moveInfoFixture() {
        guard case let .fixture(id) = info, let item = placement.placed.first(where: { $0.id == id }) else { return }
        info = nil
        placement.remove(id)
        moving = (item.fixtureId, item.transform)
        mode = .edit
        step = .parts
        sync()
    }

    private func editFromInfo(_ target: TapTarget) {
        info = nil
        mode = .edit
        if case .cable = target { step = .cables } else { step = .parts }
    }

    // MARK: Feedback

    /// Something was added: a checkmark and a success haptic.
    private func confirm(_ text: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        show(Toast(text: text, success: true))
    }

    private func note(_ text: String) {
        show(Toast(text: text, success: false))
    }

    private func show(_ message: Toast) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    /// Lights up a part for a moment so it is clear what was just placed.
    private func flash(_ id: UUID?) {
        guard let id else { return }
        placement.selectedId = id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if placement.selectedId == id, info == nil { placement.selectedId = nil }
        }
    }

    private func flashRun(_ id: UUID) {
        session.selectedRunId = id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if session.selectedRunId == id, info == nil { session.selectedRunId = nil }
        }
    }
}

extension TapTarget: Identifiable {
    var id: String {
        switch self {
        case let .fixture(id): "fixture-\(id)"
        case let .cable(id): "cable-\(id)"
        }
    }
}

/// Why the part chooser is open.
private enum ChooserPurpose: Identifiable {
    /// "Wijzig" in the parts step: pick what the "+" places next.
    case select
    /// "Wissel" in the info card.
    case replace(UUID)

    var id: String {
        switch self {
        case .select: "select"
        case let .replace(id): "replace-\(id)"
        }
    }

    var title: String {
        switch self {
        case .select: "Wat ga je plaatsen?"
        case .replace: "Vervangen door"
        }
    }
}

private struct Crosshair: View {
    let active: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 2)
                .frame(width: Theme.crosshair, height: Theme.crosshair)
            Circle().frame(width: 5, height: 5)
        }
        .foregroundStyle(active ? Theme.crosshairActive : Theme.crosshairInactive)
        .shadow(color: .black.opacity(0.6), radius: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

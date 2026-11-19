import ARKit
import AVFoundation
import SwiftUI
import UIKit

/// The one main screen: camera + crosshair, cable chip, controls and the price bar.
/// A second mode places switches and sockets on the walls.
struct MeasureScreen: View {
    enum Mode: Hashable { case measure, place }

    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var cartStore: CartStore
    @EnvironmentObject private var fixtureStore: FixtureStore
    @StateObject private var session = MeasureSession()
    /// Separate placements for AR and Demo-modus: their coordinates do not mix, and
    /// switching Demo-modus must not wipe the placements saved with the room.
    @StateObject private var arPlacement = PlacementSession()
    @StateObject private var simulatedPlacement = PlacementSession()

    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)
    @AppStorage("demoMode") private var demoMode = false
    @AppStorage("selectedCableId") private var storedCableId = ""
    @AppStorage("routeMode") private var routeMode = RouteMode.alongWall.rawValue
    @AppStorage("seenIntro") private var seenIntro = false
    @AppStorage("selectedFixtureId") private var storedFixtureId = ""
    @State private var showIntro = false

    @State private var showPicker = false
    @State private var showCart = false
    @State private var showSummary = false
    @State private var toast: String?
    @State private var mode: Mode = .measure
    @State private var showFixturePicker = false
    @State private var confirmClear = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmClearCables = false
    @State private var showEasterEgg = false

    private var cable: Cable? {
        cableStore.cables.first { $0.id == storedCableId } ?? cableStore.cables.first
    }

    private var fixture: Fixture? {
        fixtureStore.fixture(id: storedFixtureId)
            ?? fixtureStore.fixtures.first(where: \.complete)
            ?? fixtureStore.fixtures.first
    }

    private var placement: PlacementSession { useSimulated ? simulatedPlacement : arPlacement }

    private var isPlacing: Bool { mode == .place }

    private var useSimulated: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        demoMode || !ARWorldTrackingConfiguration.isSupported
        #endif
    }

    /// Live price, including the preview segment to the crosshair.
    private var quote: Quote? {
        cable.flatMap {
            PricingCalculator.quote(for: $0, measured: session.totalLength, reserve: Double(reservePercent) / 100)
        }
    }

    /// What goes into the cart: only the confirmed points, never the live preview.
    private var cartQuote: Quote? {
        guard session.points.count >= 2 else { return nil }
        return cable.flatMap {
            PricingCalculator.quote(for: $0, measured: session.confirmedLength, reserve: Double(reservePercent) / 100)
        }
    }

    private var cameraBlocked: Bool {
        !useSimulated && (cameraStatus == .denied || cameraStatus == .restricted)
    }

    private var modeBinding: Binding<RouteMode> {
        Binding(get: { RouteMode(rawValue: routeMode) ?? .alongWall },
                set: { routeMode = $0.rawValue; session.mode = $0 })
    }

    var body: some View {
        // First start: the intro comes before the camera, so the camera prompt
        // appears only after the user knows why it is needed.
        if seenIntro {
            mainScreen
                // Dark status bar text is unreadable on the camera image.
                .statusBarHidden()
                .fullScreenCover(isPresented: $showIntro) { IntroView { showIntro = false } }
        } else {
            IntroView {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                seenIntro = true
            }
        }
    }

    private var mainScreen: some View {
        ZStack {
            measureLayer
                .id(useSimulated)
                .ignoresSafeArea()

            VStack(spacing: Theme.spacing) {
                topBar
                modePicker
                statusText
                Spacer()
                // Above the buttons, in the layout: positioned under the crosshair it ended up
                // behind the buttons on an iPhone 15.
                heightLabel
                controls
                if isPlacing {
                    PlacementBar(fixture: fixture, placedCount: placement.placed.count,
                                 total: placement.total(in: fixtureStore.fixtures), persists: !useSimulated,
                                 newCount: placement.notInCart.reduce(0) { $0 + $1.count },
                                 onAddToCart: addFixturesToCart)
                } else {
                    PriceBar(cable: cable, measured: session.totalLength, quote: quote, cartQuote: cartQuote,
                             mode: modeBinding, earlierRuns: session.runs.count,
                             reservePercent: $reservePercent, onAddToCart: addToCart)
                }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 4)

            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .surface(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
            }
        }
        .overlay { if cameraBlocked { cameraBlockedCard } }
        .onChange(of: useSimulated) {
            session.reset()
            syncPlacement()
        }
        .onChange(of: mode) { syncPlacement() }
        .onChange(of: fixture?.id) { syncPlacement() }
        .onChange(of: scenePhase) { if $1 == .active { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) } }
        .onAppear {
            session.mode = RouteMode(rawValue: routeMode) ?? .alongWall
            syncPlacement()
        }
        .sheet(isPresented: $showFixturePicker) {
            FixturePickerSheet(fixtures: fixtureStore.fixtures, selectedId: Binding(
                get: { fixture?.id }, set: { storedFixtureId = $0 ?? "" }))
        }
        .confirmationDialog("Alle geplaatste schakelaars en stopcontacten wissen?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Wis alles", role: .destructive) { placement.clearAll() }
        }
        .confirmationDialog("Alle gemeten kabels wissen?", isPresented: $confirmClearCables,
                            titleVisibility: .visible) {
            Button("Wis alle kabels", role: .destructive) { session.resetAll() }
        } message: {
            Text("Wat al in de winkelmand zit, blijft daar staan.")
        }
        .sheet(isPresented: $showPicker) {
            CablePickerSheet(cables: cableStore.cables, selectedId: Binding(
                get: { cable?.id }, set: { storedCableId = $0 ?? "" }))
        }
        .sheet(isPresented: $showCart) { CartScreen() }
        .sheet(isPresented: $showSummary) {
            SummarySheet(cable: cable, quote: cartQuote, onAdd: { addToCart(); showSummary = false },
                         onContinue: { session.resume(); showSummary = false })
                .presentationDetents([.medium])
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var measureLayer: some View {
        Group {
            if useSimulated {
                SimulatedMeasureView(session: session, placement: simulatedPlacement,
                                     fixtures: fixtureStore.fixtures)
            } else {
                ARViewContainer(session: session, placement: arPlacement, fixtures: fixtureStore.fixtures)
            }
        }
        .overlay { Crosshair(active: isPlacing ? placement.canPlace : session.canAddPoint) }
    }

    /// Height of the crosshair (or of the middle of the switch preview) above the floor.
    @ViewBuilder
    private var heightLabel: some View {
        let point = isPlacing ? placement.cursor?.translation : session.cursor
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
        .allowsHitTesting(false)
    }

    private var modePicker: some View {
        Picker("Modus", selection: $mode) {
            Text("Kabel meten").tag(Mode.measure)
            Text("Schakelaars en lampen").tag(Mode.place)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .padding(3)
        .surface(RoundedRectangle(cornerRadius: 11))
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            if isPlacing { fixtureChip } else { cableChip }

            Spacer(minLength: 0)

            Button { showIntro = true } label: {
                Image(systemName: "questionmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .surface(Circle())
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Uitleg")

            cartButton
        }
        .padding(.top, 4)
    }

    private var fixtureChip: some View {
        Button { showFixturePicker = true } label: {
            HStack(spacing: 8) {
                if let fixture {
                    FixtureIcon(fixture: fixture, size: 36)
                } else {
                    Image(systemName: fixture?.isLight == true ? "lightbulb" : "lightswitch.on")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(fixture?.title ?? "Kies schakelaar of lamp").font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let fixture {
                        Text(fixture.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .surface(Capsule())
        }
        .buttonStyle(CardButtonStyle())
        .disabled(fixtureStore.fixtures.isEmpty)
    }

    private var cableChip: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(cable?.name ?? "Kies een kabel").font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let cable {
                        Text("\(cable.crossSection) · \(Format.euro(cable.pricePerMeter))/m")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .surface(Capsule())
        }
        .buttonStyle(CardButtonStyle())
        .disabled(cableStore.cables.isEmpty)
    }

    private var cartButton: some View {
        Button { showCart = true } label: {
            Image(systemName: "cart")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .surface(Circle())
                .overlay(alignment: .topTrailing) {
                    if cartStore.count > 0 {
                        Text("\(cartStore.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.onAccent)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.cta, in: Circle())
                    }
                }
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel("Winkelmand, \(cartStore.count) artikelen")
    }

    private var statusText: some View {
        VStack(spacing: 6) {
            // Long-press the title to toggle Demo-modus (hidden fallback for the stage).
            // Triple-tap: team easter egg, not saved, gone after a restart.
            Text(titleText + (showEasterEgg ? " 🍆" : ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .shadow(radius: 2)
                .onTapGesture(count: 3) { showEasterEgg.toggle() }
                .onLongPressGesture(minimumDuration: 0.8) { toggleDemoMode() }

            if let error = isPlacing ? fixtureStore.loadError : cableStore.loadError {
                pill(error, color: .red)
            } else if let message = session.trackingMessage {
                pill(message, color: Theme.warning)
            } else if isPlacing {
                if let guide = placement.guide {
                    pill(guide.label, color: Color(Theme.Token.secondary))
                } else if placement.placed.isEmpty {
                    pill(fixture?.isCeiling == true ? "Richt op het plafond en tik op +" : "Richt op een muur en tik op +",
                         color: .white)
                }
            } else if session.isFinished {
                pill("Meting klaar", color: .green)
            } else if let guide = session.guide {
                pill(guide.label, color: Color(Theme.Token.secondary))
            } else if session.points.isEmpty {
                pill(session.runs.isEmpty ? "Richt op het beginpunt en tik op +"
                                          : "Volgende kabel: richt op het beginpunt en tik op +", color: .white)
            }

            if placement.isRestoring {
                Button("Nieuwe ruimte") { placement.startNewRoom() }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .surface(Capsule())
                    .buttonStyle(CardButtonStyle())
            }

            if !isPlacing, cable?.isSample == true { SampleBadge() }
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

    @ViewBuilder
    private var controls: some View {
        if isPlacing { placementControls } else { measureControls }
    }

    private var placementControls: some View {
        HStack(alignment: .center, spacing: Theme.spacing) {
            controlButton("Ongedaan maken", icon: "arrow.uturn.backward", showsTitle: false) { placement.undo() }
                .disabled(placement.placed.isEmpty)
            controlButton("Wis alles", icon: "trash", showsTitle: false) { confirmClear = true }
                .disabled(placement.placed.isEmpty)

            Button(action: placeFixture) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: Theme.addButton, height: Theme.addButton)
                    .background(placement.canPlace && fixture != nil ? Theme.accent : Theme.secondaryButton,
                                in: Circle())
                    .foregroundStyle(Theme.onAccent)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
            }
            .disabled(!placement.canPlace || fixture == nil)
            .accessibilityLabel("Plaats \(fixture?.title ?? "schakelaar")")

            // Keeps the "+" in the same spot as in the measuring mode.
            Color.clear.frame(width: Theme.tapTarget, height: Theme.tapTarget)
        }
    }

    private var measureControls: some View {
        HStack(alignment: .center, spacing: Theme.spacing) {
            controlButton("Terug", icon: "arrow.uturn.backward") { session.undo() }
                .disabled(session.points.isEmpty)
            // With a cable in progress this clears that cable; otherwise it offers to clear the earlier ones.
            controlButton("Opnieuw", icon: "arrow.counterclockwise") {
                if session.points.isEmpty { confirmClearCables = true } else { session.reset() }
            }
            .disabled(session.points.isEmpty && session.runs.isEmpty)

            Button(action: addPoint) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: Theme.addButton, height: Theme.addButton)
                    .background(session.canAddPoint ? Theme.accent : Theme.secondaryButton, in: Circle())
                    .foregroundStyle(Theme.onAccent)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
            }
            .disabled(!session.canAddPoint)
            .accessibilityLabel("Punt toevoegen")

            controlButton("Klaar", icon: "checkmark") {
                session.finish()
                showSummary = true
            }
            .disabled(!session.canFinish)
        }
    }

    private var titleText: String {
        if useSimulated { return "Kabelmeter · Demo" }
        return session.usesLiDAR ? "Kabelmeter · LiDAR" : "Kabelmeter"
    }

    private var cameraBlockedCard: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Geen toegang tot de camera").font(.headline)
            Text("De Kabelmeter gebruikt de camera om afstanden te meten. Zet de camera aan in Instellingen.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Instellingen") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .brandProminentButton()
            Button("Gebruik demo-modus") { demoMode = true }
        }
        .padding(24)
        .surface(RoundedRectangle(cornerRadius: Theme.corner))
        .padding(32)
    }

    /// Measuring shows a short title under the icon (Terug, Opnieuw, Klaar); placing shows only
    /// the undo and trash icons. The title is always the accessibility label.
    private func controlButton(_ title: String, icon: String, showsTitle: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { ControlLabel(icon: icon, title: showsTitle ? title : nil) }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel(title)
    }

    // MARK: Actions

    private func addPoint() {
        if session.addPoint() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func placeFixture() {
        guard let fixture else { return }
        if placement.place(fixture.id) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Tells the active placement session the mode and the selected fixture; the other one stays idle.
    private func syncPlacement() {
        arPlacement.isActive = isPlacing && !useSimulated
        simulatedPlacement.isActive = isPlacing && useSimulated
        arPlacement.selectedFixtureId = fixture?.id
        simulatedPlacement.selectedFixtureId = fixture?.id
    }

    /// Adds the measured cable, keeps it visible as an earlier cable and starts the next one.
    private func addToCart() {
        guard let cable, let quote = cartQuote else { return }
        do {
            try LocalCartService(store: cartStore).add(cable: cable, meters: quote.billedLength)
            session.completeRun(cableId: cable.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show("\(Format.orderLength(quote.billedLength)) \(cable.name) toegevoegd")
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show("Toevoegen is niet gelukt")
        }
    }

    /// Adds every placed switch and socket that is not in the cart yet, as its parts.
    private func addFixturesToCart() {
        var pieces = 0
        var incomplete = 0
        for group in placement.notInCart {
            guard let fixture = fixtureStore.fixture(id: group.fixtureId) else { continue }
            let result = cartStore.add(fixture: fixture, count: group.count)
            pieces += result.pieces
            incomplete += result.incompleteFixtures
        }
        placement.markAllInCart()
        UINotificationFeedbackGenerator().notificationOccurred(incomplete > 0 ? .warning : .success)
        if incomplete > 0 {
            show("\(pieces) onderdelen toegevoegd, \(incomplete) niet compleet te bestellen")
        } else {
            show("\(pieces) onderdelen toegevoegd")
        }
    }

    private func toggleDemoMode() {
        demoMode.toggle()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        show(demoMode ? "Demo-modus aan" : "Demo-modus uit")
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == message { toast = nil } }
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

private struct SummarySheet: View {
    let cable: Cable?
    let quote: Quote?
    let onAdd: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("Samenvatting").font(.title2.bold())
            if let cable, let quote {
                Text(cable.name).font(.headline)
                row("Gemeten", Format.meters(quote.measured))
                row("Nodig met reserve", Format.meters(quote.required))
                row("Te bestellen", Format.pieces(quote.pieces))
                row("Prijs", Format.euro(quote.price))
            }
            Text("Over lange afstanden kan de meting een paar procent afwijken. Daarom rekenen we met reserve. Deze app berekent alleen een geschatte hoeveelheid materiaal. Het is geen installatieadvies. Laat de aansluiting op de groepenkast en de keuze van draaddikte en beveiliging over aan een erkend installateur.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Label("Voeg toe aan winkelmand", systemImage: "cart.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .brandProminentButton(Theme.cta)
            .buttonBorderShape(.roundedRectangle(radius: Theme.buttonCorner))
            .disabled(quote == nil)
            Button("Verder meten", action: onContinue)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.semibold)
        }
    }
}

/// White square button on the camera image with an Elektramat-blue icon, always at full
/// opacity (also when disabled), so it never turns grey on the camera image.
/// Icon only: the icons (undo, trash, reset, done) speak for themselves, and the text did not
/// fit ("Ongedaan ma…"). The title stays as the accessibility label.
private struct ControlLabel: View {
    let icon: String
    var title: String?

    /// Full color, also when disabled: a disabled button does nothing when tapped.
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font((title == nil ? Font.title2 : .title3).weight(.semibold))
                .foregroundStyle(Theme.accent)
            if let title {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: Theme.tapTarget + (title == nil ? 0 : 8), height: Theme.tapTarget)
        .surface(RoundedRectangle(cornerRadius: 14))
    }
}

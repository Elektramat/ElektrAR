import ARKit
import AVFoundation
import SwiftUI
import UIKit

/// The one main screen: camera + crosshair, cable chip, controls and the price bar.
struct MeasureScreen: View {
    @EnvironmentObject private var cableStore: CableStore
    @EnvironmentObject private var cartStore: CartStore
    @StateObject private var session = MeasureSession()

    @AppStorage("reservePercent") private var reservePercent = Int(PricingCalculator.defaultReserve * 100)
    @AppStorage("demoMode") private var demoMode = false
    @AppStorage("selectedCableId") private var storedCableId = ""
    @AppStorage("routeMode") private var routeMode = RouteMode.alongWall.rawValue
    @AppStorage("seenIntro") private var seenIntro = false
    @State private var showIntro = false

    @State private var showPicker = false
    @State private var showCart = false
    @State private var showSummary = false
    @State private var toast: String?
    @State private var confirmClear = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var cable: Cable? {
        cableStore.cables.first { $0.id == storedCableId } ?? cableStore.cables.first
    }

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
                statusText
                Spacer()
                controls
                PriceBar(cable: cable, measured: session.totalLength, quote: quote, cartQuote: cartQuote,
                         mode: modeBinding, reservePercent: $reservePercent, onAddToCart: addToCart)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 4)

            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thickMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
            }
        }
        .overlay { if cameraBlocked { cameraBlockedCard } }
        .onAppear { session.mode = RouteMode(rawValue: routeMode) ?? .alongWall }
        .onChange(of: useSimulated) { session.reset() }
        .onChange(of: scenePhase) { if $1 == .active { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) } }
        .confirmationDialog("Alle punten wissen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Wis alles", role: .destructive) { session.reset() }
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
                SimulatedMeasureView(session: session)
            } else {
                ARViewContainer(session: session)
            }
        }
        .overlay { Crosshair(active: session.canAddPoint) }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { showPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cable.connector")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cable?.name ?? "Kies een kabel").font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let cable {
                            Text("\(cable.crossSection) · \(Format.euro(cable.pricePerMeter))/m")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "chevron.down").font(.caption)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(cableStore.cables.isEmpty)

            Spacer(minLength: 0)

            Button { showIntro = true } label: {
                Image(systemName: "questionmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Uitleg")

            Button { showCart = true } label: {
                Image(systemName: "cart")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if cartStore.count > 0 {
                            Text("\(cartStore.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(Theme.onAccent)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Theme.accent, in: Circle())
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Winkelmand, \(cartStore.count) artikelen")
        }
        .padding(.top, 4)
    }

    private var statusText: some View {
        VStack(spacing: 6) {
            // Long-press the title to toggle Demo-modus (hidden fallback for the stage).
            Text(titleText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .shadow(radius: 2)
                .onLongPressGesture(minimumDuration: 0.8) { toggleDemoMode() }

            if let error = cableStore.loadError {
                pill(error, color: .red)
            } else if let message = session.trackingMessage {
                pill(message, color: Theme.warning)
            } else if session.isFinished {
                pill("Meting klaar", color: .green)
            } else if let guide = session.guide {
                pill(guide == .vertical ? "Verticaal" : "Waterpas", color: Theme.accent)
            } else if session.points.isEmpty {
                pill("Richt op het beginpunt en tik op +", color: .white)
            }

            if cable?.isSample == true { SampleBadge() }
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

    private var controls: some View {
        HStack(alignment: .center, spacing: Theme.spacing) {
            controlButton("Terug", icon: "arrow.uturn.backward") { session.undo() }
                .disabled(session.points.isEmpty)
            controlButton("Wis alles", icon: "trash") { confirmClear = true }
                .disabled(session.points.isEmpty)

            Button(action: addPoint) {
                Image(systemName: "plus")
                    .font(.system(size: 34, weight: .bold))
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
            .buttonStyle(.borderedProminent)
            Button("Gebruik demo-modus") { demoMode = true }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner))
        .padding(32)
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: Theme.tapTarget, height: Theme.tapTarget)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func addPoint() {
        if session.addPoint() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func addToCart() {
        guard let cable, let quote = cartQuote else { return }
        do {
            try LocalCartService(store: cartStore).add(cable: cable, meters: quote.billedLength)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show("\(Format.orderLength(quote.billedLength)) \(cable.name) toegevoegd")
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show("Toevoegen is niet gelukt")
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
            .buttonStyle(.borderedProminent)
            .tint(Theme.cta)
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

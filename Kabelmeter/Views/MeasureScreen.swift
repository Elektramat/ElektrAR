import ARKit
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

    @State private var showPicker = false
    @State private var showCart = false
    @State private var showSummary = false
    @State private var toast: String?

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

    private var quote: Quote? {
        cable.flatMap {
            PricingCalculator.quote(for: $0, measured: session.totalLength, reserve: Double(reservePercent) / 100)
        }
    }

    var body: some View {
        ZStack {
            measureLayer
                .id(useSimulated)
                .ignoresSafeArea()

            VStack(spacing: Theme.spacing) {
                topBar
                statusText
                Spacer()
                controls
                PriceBar(cable: cable, measured: session.totalLength, quote: quote,
                         reservePercent: $reservePercent, onAddToCart: addToCart)
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
        .onChange(of: useSimulated) { session.reset() }
        .sheet(isPresented: $showPicker) {
            CablePickerSheet(cables: cableStore.cables, selectedId: Binding(
                get: { cable?.id }, set: { storedCableId = $0 ?? "" }))
        }
        .sheet(isPresented: $showCart) { CartScreen() }
        .sheet(isPresented: $showSummary) {
            SummarySheet(cable: cable, quote: quote, onAdd: { addToCart(); showSummary = false },
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
            Text(demoMode ? "Kabelmeter · Demo" : "Kabelmeter")
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
            controlButton("Ongedaan maken", icon: "arrow.uturn.backward") { session.undo() }
                .disabled(session.points.isEmpty)
            controlButton("Opnieuw", icon: "arrow.counterclockwise") { session.reset() }
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
        guard let cable, let quote else { return }
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
            Text("Over lange afstanden kan de meting een paar procent afwijken. Daarom rekenen we met reserve. Dit is een schatting: laat het aansluiten over aan een installateur.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Label("Voeg toe aan winkelmand", systemImage: "cart.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .buttonStyle(.borderedProminent)
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

import AVFoundation
import SwiftUI

/// Shown once at the first start: three steps, why the app needs the camera, and one button
/// that asks for camera access. Also reachable via the "?" button on the rooms screen.
struct IntroView: View {
    /// Called after the user tapped "Start meten" and answered the camera prompt.
    let onStart: () -> Void
    @State private var asking = false

    private let steps: [(icon: String, title: String, text: String)] = [
        ("square.split.bottomrightquarter", "Maak een ruimte", "Woonkamer, keuken… Elke ruimte is een eigen ontwerp."),
        ("lightswitch.on", "Plaats je onderdelen", "Richt op de muur en tik op +: schakelaars, stopcontacten en lampen, op de juiste hoogte."),
        ("cable.connector", "Trek de kabels", "Automatisch vanaf de groepenkast, of zelf met een + bij elke hoek. De winkelwagen rekent alles samen."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        stepRow(number: index + 1, icon: step.icon, title: step.title, text: step.text)
                    }

                    Label {
                        Text("De app gebruikt de camera om afstanden te meten. Beelden worden niet opgeslagen of verstuurd.")
                    } icon: {
                        Image(systemName: "camera.fill").foregroundStyle(Theme.accent)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(Theme.spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brandSurfaceSoft, in: RoundedRectangle(cornerRadius: Theme.buttonCorner))
                }
                .padding(24)
            }

            Button(action: start) {
                Text("Aan de slag")
                    .font(.headline.weight(.heavy))
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .brandProminentButton(Theme.cta)
            .buttonBorderShape(.roundedRectangle(radius: Theme.buttonCorner))
            .disabled(asking)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Text("Een schatting van materiaal, geen installatieadvies.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .background(Theme.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Elektramat")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white.opacity(0.85))
            Text("Kabelmeter")
                .font(Theme.branded(.largeTitle))
                .foregroundStyle(.white)
            Text("Nooit te weinig of te veel materiaal. Ontwerp je ruimte één keer en alles staat in je winkelwagen.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .background(Theme.brandSurface)
    }

    private func stepRow(number: Int, icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .labelStyle(.titleOnly)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stap \(number): \(title). \(text)")
    }

    private func start() {
        guard !asking else { return }
        // Ask for the camera here, right after explaining why. If the user already
        // answered before, iOS does not ask again and the camera card handles "denied".
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            onStart()
            return
        }
        asking = true
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in
                asking = false
                onStart()
            }
        }
    }
}

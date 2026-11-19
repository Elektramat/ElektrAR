import SwiftUI
import WebKit

/// Adds the cart lines to elektramat.nl, shows the result at once, and shows the shop
/// cart (loaded in the background meanwhile) when the user asks for it.
struct WebShopSheet: View {
    let lines: [WebShopLine]
    /// Owned by the cart screen, so the web view is already warmed up when this opens.
    @ObservedObject var shop: WebShopCart
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Always in the hierarchy so the cart page can load in the background.
                WebView(webView: shop.webView).ignoresSafeArea(edges: .bottom)
                    .opacity(shop.phase == .cart ? 1 : 0)
                    .allowsHitTesting(shop.phase == .cart)
                    .overlay(alignment: .top) {
                        // Shows that a tap in the shop (trash, quantity, checkout) is working.
                        if shop.phase == .cart, shop.cartPageReady, let progress = shop.pageProgress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(Theme.accent)
                                .animation(.easeOut(duration: 0.2), value: progress)
                        }
                    }

                switch shop.phase {
                case .idle, .connecting: progress(step: nil)
                case let .adding(index, total): progress(step: total > 1 ? "\(index) van \(total)" : nil)
                case .added: result
                case .cart:
                    if !shop.cartPageReady { ProgressView("Winkelmand laden…").controlSize(.large) }
                }
            }
            .background(Color(Theme.Token.black5))
            .navigationTitle("elektramat.nl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
        }
        .task { await shop.run(lines) }
    }

    private func progress(step: String?) -> some View {
        VStack(spacing: Theme.spacing) {
            ProgressView().controlSize(.large)
            Text(lines.count == 1 ? "Kabel in je winkelmand zetten…" : "Kabels in je winkelmand zetten…")
                .font(.headline)
            if let step { Text(step).foregroundStyle(Theme.inkSecondary) }
        }
        .padding(24)
        .surface(RoundedRectangle(cornerRadius: Theme.corner))
    }

    private var result: some View {
        VStack(spacing: Theme.spacing) {
            if shop.addedCount > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.cta)
                Text(shop.addedCount == 1 ? "1 product staat in je winkelmand"
                                          : "\(shop.addedCount) producten staan in je winkelmand")
                    .font(.title3.weight(.heavy))
                    .multilineTextAlignment(.center)
                Text("op elektramat.nl")
                    .foregroundStyle(Theme.inkSecondary)
            }

            if !shop.failures.isEmpty { failureList }

            Button { shop.showCart() } label: {
                Label("Bekijk winkelmand en reken af", systemImage: "cart")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            }
            .brandProminentButton(Theme.cta)
            .buttonBorderShape(.roundedRectangle(radius: Theme.buttonCorner))
            .padding(.top, 8)

            Button("Verder meten") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Theme.accent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .surface(RoundedRectangle(cornerRadius: Theme.corner))
        .padding(Theme.spacing)
    }

    private var failureList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Niet alles staat in je winkelmand", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(shop.failures) { failure in
                Text("\(failure.name): \(failure.reason)").font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(Theme.warning.opacity(0.2), in: RoundedRectangle(cornerRadius: Theme.buttonCorner))
        .foregroundStyle(Theme.ink)
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

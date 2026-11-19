import SwiftUI
import WebKit

/// Shows elektramat.nl in the app while the cart lines are added, then the shop cart.
struct WebShopSheet: View {
    let lines: [WebShopLine]
    @StateObject private var shop = WebShopCart()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WebView(webView: shop.webView).ignoresSafeArea(edges: .bottom)
                if case let .adding(index, total) = shop.phase {
                    progress(index: index, total: total)
                }
            }
            .safeAreaInset(edge: .top) {
                if shop.phase == .done && !shop.failures.isEmpty { failureBanner }
            }
            .navigationTitle("elektramat.nl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
        }
        .task { await shop.run(lines) }
    }

    private func progress(index: Int, total: Int) -> some View {
        VStack(spacing: Theme.spacing) {
            ProgressView().controlSize(.large)
            Text("Kabel in je winkelmand zetten…").font(.headline)
            if total > 1 { Text("\(index) van \(total)").foregroundStyle(.secondary) }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private var failureBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Niet alles staat in je winkelmand", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(shop.failures) { failure in
                Text("\(failure.name): \(failure.reason)").font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(Theme.warning.opacity(0.9))
        .foregroundStyle(.black)
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

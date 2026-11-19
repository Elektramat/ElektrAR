import Combine
import Foundation
import WebKit

/// Puts the in-app cart into the real elektramat.nl cart.
///
/// The shop (Magento with Hyvä) only accepts its product form with a session form key, so a
/// link from Safari cannot fill the cart. Instead this loads each product page in a web view
/// owned by the app, posts the page's own add-to-cart form with the right quantity, and checks
/// the cart through Magento's customer section endpoint. The cart lives in this web view's
/// cookie store (persisted), not in Safari; the user checks out in the same web view.
///
/// TODO: for production, ask the webshop team for a deep link (for example
/// /kabelmeter/add?sku=…&qty=…) or a cart API with a hand-off to the browser session.
@MainActor
final class WebShopCart: NSObject, ObservableObject, WKNavigationDelegate {
    enum Phase: Equatable {
        case idle
        case adding(index: Int, total: Int)
        case done
    }

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let reason: String
    }

    static let cartUrl = URL(string: "https://www.elektramat.nl/checkout/cart/")!
    private static let pageTimeout: TimeInterval = 30

    let webView: WKWebView
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var failures: [Failure] = []

    private var pageLoad: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // keeps the shop cart between app launches
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    /// Adds every line, then shows the shop cart. Runs once per instance.
    func run(_ lines: [WebShopLine]) async {
        guard phase == .idle else { return }
        for (index, line) in lines.enumerated() {
            phase = .adding(index: index + 1, total: lines.count)
            do {
                try await load(line.productUrl)
                let result = try await webView.callAsyncJavaScript(
                    Self.addToCartScript,
                    arguments: ["qty": line.quantity, "sku": line.sku],
                    contentWorld: .page)
                if let reason = Self.failureReason(result, expected: line.quantity) {
                    failures.append(Failure(name: line.name, reason: reason))
                }
            } catch {
                failures.append(Failure(name: line.name, reason: "De pagina laadde niet (\(error.localizedDescription))."))
            }
        }
        phase = .done
        try? await load(Self.cartUrl)
    }

    private static func failureReason(_ result: Any?, expected: Int) -> String? {
        guard let dict = result as? [String: Any] else { return "Onverwacht antwoord van de webshop." }
        if let error = dict["error"] as? String {
            switch error {
            case "no-form": return "Dit product kan nu niet besteld worden (geen bestelknop op de pagina)."
            case "timeout": return "De webshop reageerde niet op tijd."
            default: return "De webshop gaf een fout (\(error))."
            }
        }
        let before = (dict["before"] as? NSNumber)?.intValue ?? 0
        let after = (dict["after"] as? NSNumber)?.intValue ?? 0
        return after - before >= expected ? nil : "De webshop nam \(after - before) van \(expected) m over."
    }

    private func load(_ url: URL) async throws {
        pageLoad?.resume(throwing: CancellationError())
        try await withCheckedThrowingContinuation { continuation in
            pageLoad = continuation
            webView.load(URLRequest(url: url, timeoutInterval: Self.pageTimeout))
        }
    }

    private func finishPageLoad(_ error: Error?) {
        guard let continuation = pageLoad else { return }
        pageLoad = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishPageLoad(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishPageLoad(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        MainActor.assumeIsolated { finishPageLoad(error) }
    }

    /// Runs in the product page. Posts the page's add-to-cart form with `qty`, and returns the
    /// quantity of `sku` in the cart before and after, read from Magento's customer section.
    private static let addToCartScript = """
    const form = document.getElementById('product_addtocart_form');
    if (!form) { return { error: 'no-form' }; }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    const cartQty = async () => {
        const r = await fetch('/customer/section/load/?sections=cart&force_new_section_timestamp=true',
            { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' }, signal: controller.signal });
        if (!r.ok) { throw new Error('section-' + r.status); }
        const items = ((await r.json()).cart || {}).items || [];
        return items.filter(i => i.product_sku === sku).reduce((sum, i) => sum + Number(i.qty || 0), 0);
    };
    try {
        const before = await cartQty();
        const data = new FormData(form);
        data.set('qty', String(qty));
        if (window.hyva && typeof hyva.getFormKey === 'function') { data.set('form_key', hyva.getFormKey()); }
        const r = await fetch(form.action, { method: 'POST', body: data, credentials: 'same-origin', signal: controller.signal });
        if (!r.ok) { return { error: 'http-' + r.status }; }
        const after = await cartQty();
        return { before, after };
    } catch (e) {
        return { error: e.name === 'AbortError' ? 'timeout' : String(e.message || e) };
    } finally {
        clearTimeout(timer);
    }
    """
}

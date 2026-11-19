import Combine
import Foundation
import WebKit

/// Puts the in-app cart into the real elektramat.nl cart.
///
/// The shop (Magento with Hyvä) only accepts its add-to-cart form with a form key that matches
/// the session cookie, so a link from Safari cannot fill the cart. Instead this works inside a
/// web view owned by the app. To keep it fast it renders no product page:
/// 1. Load a tiny page on the shop's domain (robots.txt, 7 KB) to run scripts as the shop.
/// 2. Read the cart quantities from Magento's customer section (about 1 KB).
/// 3. Post the add-to-cart form per cable without following the redirect (which would
///    download the 2.7 MB product page again).
/// 4. Read the cart again, report every cable that did not arrive, and show the cart page.
/// Measured with curl on 19 Nov 2026: about 2 s for one cable instead of about 7 s.
///
/// The cart lives in this web view's cookie store (persisted), not in Safari; the user checks
/// out in the same web view.
///
/// TODO: for production, ask the webshop team for a deep link (for example
/// /kabelmeter/add?sku=…&qty=…) or a cart API with a hand-off to the browser session.
@MainActor
final class WebShopCart: NSObject, ObservableObject, WKNavigationDelegate {
    enum Phase: Equatable {
        case idle
        case connecting
        case adding(index: Int, total: Int)
        case done
    }

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let reason: String
    }

    static let cartUrl = URL(string: "https://www.elektramat.nl/checkout/cart/")!
    private static let sessionUrl = URL(string: "https://www.elektramat.nl/robots.txt")!
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

    /// Adds every line, checks the cart, then shows the shop cart. Runs once per instance.
    func run(_ lines: [WebShopLine]) async {
        guard phase == .idle else { return }
        phase = .connecting
        defer { phase = .done }
        do {
            try await load(Self.sessionUrl)
            let before = try await cartQuantities()
            var posted: [WebShopLine] = []
            for (index, line) in lines.enumerated() {
                phase = .adding(index: index + 1, total: lines.count)
                if let reason = try await post(line) {
                    failures.append(Failure(name: line.name, reason: reason))
                } else {
                    posted.append(line)
                }
            }
            let after = try await cartQuantities()
            failures += WebShopOrder.missing(posted, before: before, after: after).map {
                Failure(name: $0.line.name, reason: "De webshop nam \($0.arrived) van \($0.line.quantity) m over.")
            }
        } catch {
            failures.append(Failure(name: "Webshop", reason: "Geen verbinding met elektramat.nl (\(error.localizedDescription))."))
        }
        try? await load(Self.cartUrl)
    }

    // MARK: Steps

    private func cartQuantities() async throws -> [String: Int] {
        let result = try await webView.callAsyncJavaScript(Self.cartQuantitiesScript, arguments: [:], contentWorld: .page)
        guard let dict = result as? [String: Any] else { throw WebShopError.unexpectedAnswer }
        if let error = dict["error"] as? String { throw WebShopError.shop(error) }
        let items = dict["items"] as? [String: Any] ?? [:]
        return items.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    /// Returns nil when the form was accepted, otherwise a reason for the user.
    private func post(_ line: WebShopLine) async throws -> String? {
        var arguments: [String: Any] = ["qty": line.quantity, "productUrl": line.productUrl.absoluteString]
        if let id = line.productId { arguments["productId"] = id }
        let result = try await webView.callAsyncJavaScript(Self.addScript, arguments: arguments, contentWorld: .page)
        guard let dict = result as? [String: Any] else { return "Onverwacht antwoord van de webshop." }
        switch dict["error"] as? String {
        case nil: return nil
        case "no-form": return "Dit product kan nu niet besteld worden (geen bestelknop op de pagina)."
        case "timeout": return "De webshop reageerde niet op tijd."
        case let error?: return "De webshop gaf een fout (\(error))."
        }
    }

    // MARK: Page loading

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

    // MARK: Scripts (run on www.elektramat.nl)

    /// Quantity per SKU in the shop cart, from Magento's customer section.
    private static let cartQuantitiesScript = """
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
        const r = await fetch('/customer/section/load/?sections=cart&force_new_section_timestamp=true',
            { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' }, signal: controller.signal });
        if (!r.ok) { return { error: 'section-' + r.status }; }
        const items = {};
        for (const i of ((await r.json()).cart || {}).items || []) {
            items[i.product_sku] = (items[i.product_sku] || 0) + Number(i.qty || 0);
        }
        return { items };
    } catch (e) {
        return { error: e.name === 'AbortError' ? 'timeout' : String(e.message || e) };
    } finally {
        clearTimeout(timer);
    }
    """

    /// Posts the add-to-cart form for one product. Uses the form key cookie the shop's own
    /// scripts use (creates it when missing, like Hyvä does). Reads the product id from the
    /// product page only when the catalog has none.
    private static let addScript = """
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    try {
        let formKey = (document.cookie.match(/(?:^|; )form_key=([^;]+)/) || [])[1];
        if (!formKey) {
            const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
            formKey = Array.from(crypto.getRandomValues(new Uint8Array(16)), b => chars[b % chars.length]).join('');
            document.cookie = 'form_key=' + formKey + '; path=/; secure; samesite=lax';
        }
        let id = typeof productId === 'number' ? productId : null;
        if (id === null) {
            const page = await (await fetch(productUrl, { credentials: 'same-origin', signal: controller.signal })).text();
            const match = page.match(/action="[^"]*\\/checkout\\/cart\\/add\\/[^"]*\\/product\\/(\\d+)\\/"\\s*id="product_addtocart_form"/);
            if (!match) { return { error: 'no-form' }; }
            id = Number(match[1]);
        }
        const body = new FormData();
        body.set('product', String(id));
        body.set('qty', String(qty));
        body.set('form_key', formKey);
        const r = await fetch('/checkout/cart/add/product/' + id + '/',
            { method: 'POST', body, credentials: 'same-origin', redirect: 'manual', signal: controller.signal });
        if (r.type !== 'opaqueredirect' && !r.ok) { return { error: 'http-' + r.status }; }
        return {};
    } catch (e) {
        return { error: e.name === 'AbortError' ? 'timeout' : String(e.message || e) };
    } finally {
        clearTimeout(timer);
    }
    """
}

private enum WebShopError: LocalizedError {
    case unexpectedAnswer
    case shop(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedAnswer: "onverwacht antwoord"
        case let .shop(code): code
        }
    }
}

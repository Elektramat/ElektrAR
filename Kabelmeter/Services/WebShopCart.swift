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
/// 4. Read the cart again and report every cable that did not arrive.
/// Measured with curl on 19 Nov 2026: about 2 s for one cable instead of about 7 s.
///
/// Two more speed-ups (19 Nov 2026):
/// - `warmUp()` starts the web view and the session page as soon as the cart screen opens,
///   so the web process start and TLS handshake are done before the user taps.
/// - After the posts the sheet shows a native "added" screen at once. The cart page
///   (2.6 MB HTML, 1.4 to 2.3 s on fast wifi) loads in the background and is shown only
///   when the user taps "Bekijk winkelmand en reken af".
///
/// The cart lives in this web view's cookie store (persisted), not in Safari; the user checks
/// out in the same web view.
///
/// TODO: for production, ask the webshop team for a deep link (for example
/// /kabelmeter/add?sku=…&qty=…) or a cart API with a hand-off to the browser session.
@MainActor
final class WebShopCart: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum Phase: Equatable {
        case idle
        case connecting
        case adding(index: Int, total: Int)
        /// Posts are done; the native result screen shows. The cart page may still be loading.
        case added
        /// The user asked to see the shop cart.
        case cart
    }

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let reason: String
    }

    static let cartUrl = URL(string: "https://www.elektramat.nl/checkout/cart/")!
    private static let sessionUrl = URL(string: "https://www.elektramat.nl/robots.txt")!
    private static let shopHost = "www.elektramat.nl"
    private static let pageTimeout: TimeInterval = 30

    let webView: WKWebView
    @Published private(set) var phase: Phase = .idle
    /// Loading progress of the page the user sees (0...1), nil when nothing loads. After a tap
    /// in the shop (for example the trash button) the cart page reloads for a few seconds;
    /// without a progress bar the button looked dead.
    @Published private(set) var pageProgress: Double?
    private var observers: [NSKeyValueObservation] = []
    @Published private(set) var failures: [Failure] = []
    /// Cables that are in the shop cart after this run (posted and confirmed by the cart check).
    @Published private(set) var addedCount = 0
    /// True once the cart page finished loading in the background.
    @Published private(set) var cartPageReady = false
    /// True while the web view shows the session page (robots.txt). That plain-text page must
    /// never be visible: the sheet keeps the web view hidden until a shop page is loaded.
    @Published private(set) var isOnSessionPage = false

    private var pageLoad: CheckedContinuation<Void, Error>?
    private var sessionTask: Task<Void, Error>?

    var isBusy: Bool {
        switch phase {
        case .connecting, .adding: true
        case .idle, .added, .cart: false
        }
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // keeps the shop cart between app launches
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        // Without a UI delegate a web view ignores alert/confirm dialogs (confirm returns false)
        // and links that open a new window, so shop buttons that use them do nothing.
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // WKWebView reports these key-value changes on the main thread.
        observers = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.updateProgress(view) }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.updateProgress(view) }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.urlChanged(view.url) }
            },
        ]
    }

    private func updateProgress(_ view: WKWebView) {
        pageProgress = view.isLoading ? max(view.estimatedProgress, 0.05) : nil
    }

    // MARK: Dialogs and new windows from the shop page

    nonisolated func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                             initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        MainActor.assumeIsolated {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            guard Self.present(alert) else { return completionHandler() }
        }
    }

    nonisolated func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                             initiatedByFrame frame: WKFrameInfo,
                             completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        MainActor.assumeIsolated {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Annuleer", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            guard Self.present(alert) else { return completionHandler(false) }
        }
    }

    /// Links with target="_blank" or window.open: open them in this same web view.
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        }
        return nil
    }

    /// Shows a dialog on top of whatever is on screen (the shop sheet). False when there is
    /// no window to show it in.
    private static func present(_ controller: UIViewController) -> Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard var top = window?.rootViewController else { return false }
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
        return true
    }

    /// Starts the web view and loads the session page in the background. Safe to call often.
    func warmUp() {
        guard sessionTask == nil, !isBusy else { return }
        sessionTask = Task { try await self.load(Self.sessionUrl) }
    }

    /// Adds every line and checks the cart, then shows the result at once and loads the
    /// cart page in the background. Can run again later with new lines.
    func run(_ lines: [WebShopLine]) async {
        guard !isBusy else { return }
        failures = []
        addedCount = 0
        cartPageReady = false
        phase = .connecting
        do {
            try await ensureSession()
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
            let missing = WebShopOrder.missing(posted, before: before, after: after)
            failures += missing.map {
                Failure(name: $0.line.name, reason: "De webshop nam \($0.arrived) van \($0.line.quantity) over.")
            }
            addedCount = posted.count - missing.count
        } catch {
            failures.append(Failure(name: "Webshop", reason: "Geen verbinding met elektramat.nl (\(error.localizedDescription))."))
        }
        phase = .added
        Task { await loadCartPage() }
    }

    /// Shows the shop cart; the page is already loading or loaded. When the cart page load was
    /// cut off and the web view still shows the session page, loads the cart again.
    func showCart() {
        phase = .cart
        if cartPageReady, isOnSessionPage, !webView.isLoading {
            Task { await loadCartPage() }
        }
    }

    private func loadCartPage() async {
        cartPageReady = false
        // A failed load still shows the web view, which then shows the browser's error.
        try? await load(Self.cartUrl)
        cartPageReady = true
    }

    /// Swiping back from the cart lands on the session page in the history: load the cart again.
    private func urlChanged(_ url: URL?) {
        isOnSessionPage = url?.path == Self.sessionUrl.path
        if isOnSessionPage, phase == .cart, cartPageReady {
            Task { await loadCartPage() }
        }
    }

    /// The sheet shows the web view only on a real shop page, never the session page.
    var showsWebView: Bool { phase == .cart && cartPageReady && !isOnSessionPage }

    /// Reuses the warmed-up session page. Loads it again when the warm-up failed or the
    /// web view left the shop (for example to a payment page), because the scripts must run
    /// on www.elektramat.nl.
    private func ensureSession() async throws {
        if let task = sessionTask, webView.url?.host == Self.shopHost || webView.url == nil {
            do {
                try await task.value
                if webView.url?.host == Self.shopHost { return }
            } catch {
                // Fall through and try once more.
            }
        }
        let task = Task { try await self.load(Self.sessionUrl) }
        sessionTask = task
        try await task.value
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

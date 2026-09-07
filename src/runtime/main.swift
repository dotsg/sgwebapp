import Cocoa
import WebKit

// MARK: - Color helpers

func parseHexColor(_ hexString: String) -> NSColor {
    var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if clean.hasPrefix("0x") {
        clean = String(clean.dropFirst(2))
    } else if clean.hasPrefix("#") {
        clean = String(clean.dropFirst(1))
    }
    guard let hex = UInt64(clean, radix: 16) else {
        return NSColor(red: 0.54, green: 0.71, blue: 0.98, alpha: 1.0) // default 89b4fa
    }
    if clean.count == 6 {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    } else if clean.count == 8 {
        let a = CGFloat((hex >> 24) & 0xFF) / 255.0
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
    return NSColor(red: 0.54, green: 0.71, blue: 0.98, alpha: 1.0)
}

/// Config root, overridable so the test suite never reads the user's real one.
func sgwebappConfigDir() -> URL {
    if let override = ProcessInfo.processInfo.environment["SGWEBAPP_CONFIG_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/sgwebapp")
}

func readGlobalConfig() -> [String: Any] {
    let configFile = sgwebappConfigDir().appendingPathComponent("config.json")
    guard let data = try? Data(contentsOf: configFile),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

func resolveBorderColor(_ colorSpec: String, appearance: NSAppearance?) -> CGColor {
    let clean = colorSpec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if clean == "tahoe" || clean == "auto" || clean == "system" {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(white: 1.0, alpha: 0.18).cgColor
        } else {
            // In Light Mode, native macOS windows rely purely on the WindowServer drop shadow
            // for window delineation. Drawing an artificial inner CALayer stroke creates a muddy
            // double border (especially on non-Retina displays).
            return NSColor.clear.cgColor
        }
    }
    return parseHexColor(clean).cgColor
}

// MARK: - Cookie jar
//
// WebKit scopes every data store under ~/Library/WebKit/<bundle-id>/, so two
// sgwebapp bundles can never share a login by pointing at the same store.
// Instead we sync cookies for a small set of SSO domains through a jar file:
// import on launch, export on quit. See docs/cookies.md.

struct JarCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Double?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?

    var key: String { "\(domain)\u{1}\(path)\u{1}\(name)" }

    init?(_ c: HTTPCookie) {
        guard !c.isSessionOnly else { return nil }
        name = c.name
        value = c.value
        domain = c.domain
        path = c.path
        expires = c.expiresDate?.timeIntervalSince1970
        secure = c.isSecure
        httpOnly = c.isHTTPOnly
        if #available(macOS 10.15, *) {
            switch c.sameSitePolicy {
            case HTTPCookieStringPolicy.sameSiteStrict?: sameSite = "Strict"
            case HTTPCookieStringPolicy.sameSiteLax?: sameSite = "Lax"
            default: sameSite = nil
            }
        }
    }

    func toHTTPCookie() -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
        ]
        if let e = expires { props[.expires] = Date(timeIntervalSince1970: e) }
        if secure { props[.secure] = "TRUE" }
        if #available(macOS 10.15, *) {
            switch sameSite {
            case "Strict": props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
            case "Lax": props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
            default: break
            }
        }
        // HTTPCookie has no public httpOnly property key; the flag is preserved
        // in the jar so a future writer can use it, but WebKit will re-derive it.
        return HTTPCookie(properties: props)
    }
}

struct CookieJar: Codable {
    var version: Int = 1
    var cookies: [JarCookie] = []
}

enum CookieStore {
    static var configDir: URL { sgwebappConfigDir() }
    static var jarURL: URL { configDir.appendingPathComponent("cookiejar.json") }
    static func pendingURL(bundleID: String) -> URL {
        configDir.appendingPathComponent("pending/\(bundleID).json")
    }

    static func load(_ url: URL) -> CookieJar? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CookieJar.self, from: data)
    }

    static func save(_ jar: CookieJar, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(jar) else { return }
        // Write 0600 from the start; never let the jar exist world-readable.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Cookie domains that carry a shared sign-in across different web apps.
/// A cookie is synced only if its domain matches one of these suffixes.
func defaultSharedDomains() -> [String] {
    ["google.com", "accounts.google.com", "github.com", "githubusercontent.com",
     "login.microsoftonline.com", "microsoft.com", "live.com",
     "appleid.apple.com", "okta.com", "auth0.com", "slack.com", "atlassian.com"]
}

func domainMatches(_ cookieDomain: String, suffixes: [String]) -> Bool {
    let d = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
    let lower = d.lowercased()
    for s in suffixes {
        let suffix = s.lowercased()
        if lower == suffix || lower.hasSuffix("." + suffix) { return true }
    }
    return false
}

// MARK: - Configuration

let globalConfig = readGlobalConfig()

var targetURLString = Bundle.main.object(forInfoDictionaryKey: "SGWebAppURL") as? String ?? "https://example.com"
var appTitle = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Web App"
var borderColorHex = Bundle.main.object(forInfoDictionaryKey: "SGWebAppBorderColor") as? String
    ?? globalConfig["border_color"] as? String
    ?? "tahoe"

var borderWidth: CGFloat = {
    if let w = Bundle.main.object(forInfoDictionaryKey: "SGWebAppBorderWidth") as? Double { return CGFloat(w) }
    if let n = Bundle.main.object(forInfoDictionaryKey: "SGWebAppBorderWidth") as? NSNumber { return CGFloat(n.doubleValue) }
    if let w = globalConfig["border_width"] as? Double { return CGFloat(w) }
    if let n = globalConfig["border_width"] as? NSNumber { return CGFloat(n.doubleValue) }
    return 0.5
}()

var cornerRadius: CGFloat = {
    if let r = Bundle.main.object(forInfoDictionaryKey: "SGWebAppCornerRadius") as? Double { return CGFloat(r) }
    if let n = Bundle.main.object(forInfoDictionaryKey: "SGWebAppCornerRadius") as? NSNumber { return CGFloat(n.doubleValue) }
    if let r = globalConfig["border_radius"] as? Double { return CGFloat(r) }
    if let n = globalConfig["border_radius"] as? NSNumber { return CGFloat(n.doubleValue) }
    return 26.0
}()

var contentPadding: CGFloat = {
    if let p = Bundle.main.object(forInfoDictionaryKey: "SGWebAppPadding") as? Double { return CGFloat(p) }
    if let n = Bundle.main.object(forInfoDictionaryKey: "SGWebAppPadding") as? NSNumber { return CGFloat(n.doubleValue) }
    if let p = globalConfig["padding"] as? Double { return CGFloat(p) }
    if let n = globalConfig["padding"] as? NSNumber { return CGFloat(n.doubleValue) }
    return 8.0
}()

var shareLogin: Bool = {
    if let s = Bundle.main.object(forInfoDictionaryKey: "SGWebAppShareLogin") as? Bool { return s }
    if let s = globalConfig["share_login"] as? Bool { return s }
    if let n = globalConfig["share_login"] as? NSNumber { return n.boolValue }
    return true
}()

var sharedDomains: [String] = {
    if let d = globalConfig["shared_cookie_domains"] as? [String], !d.isEmpty { return d }
    return defaultSharedDomains()
}()

var customUserAgent: String? = {
    if let ua = Bundle.main.object(forInfoDictionaryKey: "SGWebAppUserAgent") as? String, !ua.isEmpty {
        return ua
    }
    if let ua = globalConfig["user_agent"] as? String, !ua.isEmpty {
        return ua
    }
    return nil
}()

func resolveDefaultUserAgent() -> String {
    // Default WKWebView UA lacks "Version/<ver> Safari/<build>", causing sites like
    // WhatsApp Web to report "WhatsApp works with Safari 15+ - please update Safari".
    // We synthesize a complete, modern Safari desktop user agent.
    var safariVersion = "18.3"
    if let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist"),
       let ver = info["CFBundleShortVersionString"] as? String, !ver.isEmpty {
        safariVersion = ver
    }
    return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Safari/605.1.15"
}

var windowWidth: CGFloat = 1200
var windowHeight: CGFloat = 800
var explicitWindowSize = false

var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--url":
        if let val = args.first { targetURLString = val; args = args.dropFirst() }
    case "--title", "--name":
        if let val = args.first { appTitle = val; args = args.dropFirst() }
    case "--border-color", "--color":
        if let val = args.first { borderColorHex = val; args = args.dropFirst() }
    case "--border-width", "--width":
        if let val = args.first, let w = Double(val) { borderWidth = CGFloat(w); args = args.dropFirst() }
    case "--border-radius", "--radius":
        if let val = args.first, let r = Double(val) { cornerRadius = CGFloat(r); args = args.dropFirst() }
    case "--padding":
        if let val = args.first, let p = Double(val) { contentPadding = CGFloat(p); args = args.dropFirst() }
    case "--win-width":
        if let val = args.first, let w = Double(val) { windowWidth = CGFloat(w); explicitWindowSize = true; args = args.dropFirst() }
    case "--win-height":
        if let val = args.first, let h = Double(val) { windowHeight = CGFloat(h); explicitWindowSize = true; args = args.dropFirst() }
    case "--user-agent", "--ua":
        if let val = args.first { customUserAgent = val; args = args.dropFirst() }
    case "--no-share-login":
        shareLogin = false
    default:
        if targetURLString == "https://example.com" && arg.hasPrefix("http") {
            targetURLString = arg
        }
    }
}

// MARK: - Views and windows

class FramelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class TopDraggableView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

class BorderView: NSView {
    let borderOverlay = CALayer()
    let maskLayer = CALayer()
    let webMaskLayer = CALayer()
    let visualEffectView = NSVisualEffectView()
    weak var webView: WKWebView?
    var currentBorderWidth: CGFloat = 0.5
    var currentCornerRadius: CGFloat = 26.0
    var currentPadding: CGFloat = 8.0
    var colorSpec: String = "tahoe"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        visualEffectView.frame = bounds
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .windowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        addSubview(visualEffectView, positioned: .below, relativeTo: nil)

        maskLayer.backgroundColor = NSColor.black.cgColor
        maskLayer.cornerCurve = .continuous
        layer?.mask = maskLayer
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        webMaskLayer.backgroundColor = NSColor.black.cgColor
        webMaskLayer.cornerCurve = .continuous

        borderOverlay.cornerCurve = .continuous
        borderOverlay.zPosition = 999
        layer?.addSublayer(borderOverlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateBorder(width: CGFloat, radius: CGFloat, padding: CGFloat, colorSpec: String) {
        currentBorderWidth = width
        currentCornerRadius = radius
        currentPadding = padding
        self.colorSpec = colorSpec

        let resolvedColor = resolveBorderColor(colorSpec, appearance: effectiveAppearance)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        visualEffectView.frame = bounds

        maskLayer.frame = bounds
        maskLayer.cornerRadius = radius
        layer?.cornerRadius = radius

        borderOverlay.frame = bounds
        borderOverlay.cornerRadius = radius
        borderOverlay.borderWidth = width
        borderOverlay.borderColor = resolvedColor
        borderOverlay.isHidden = (resolvedColor.alpha == 0)

        let totalInset = padding > 0 ? padding : width
        if let wv = webView {
            wv.frame = bounds.insetBy(dx: totalInset, dy: totalInset)
            let innerRadius = max(0, radius - totalInset)
            webMaskLayer.frame = wv.bounds
            webMaskLayer.cornerRadius = innerRadius
            wv.layer?.mask = innerRadius > 0 ? webMaskLayer : nil
            wv.layer?.cornerRadius = innerRadius
            wv.layer?.cornerCurve = .continuous
            wv.layer?.masksToBounds = true
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        updateBorder(width: currentBorderWidth, radius: currentCornerRadius, padding: currentPadding, colorSpec: colorSpec)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder(width: currentBorderWidth, radius: currentCornerRadius, padding: currentPadding, colorSpec: colorSpec)
    }
}

/// A popup window for `window.open()` / `target="_blank"` — most commonly an
/// OAuth consent screen. Deliberately a normal titled window: the user needs to
/// see the address and be able to close it.
final class PopupWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    private var retained: PopupWindowController?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    init(webView: WKWebView, features: WKWindowFeatures) {
        self.webView = webView
        let w = features.width?.doubleValue ?? 520
        let h = features.height?.doubleValue ?? 640
        let rect = NSRect(x: 0, y: 0, width: max(360, w), height: max(400, h))
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Sign in"
        window.contentView = webView
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        retained = self

        // Track the page: an auth flow redirects through several hosts, and a
        // window frozen at "Sign in" tells the user nothing about where their
        // credentials are going. The subtitle carries the host, which is the
        // closest thing to an address bar a popup can offer.
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
            guard let title = wv.title, !title.isEmpty else { return }
            self?.window.title = title
        }
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
            self?.window.subtitle = wv.url?.host ?? ""
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        titleObservation = nil
        urlObservation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        // Break the self-reference that keeps the controller alive.
        DispatchQueue.main.async { self.retained = nil }
    }
}

// MARK: - Error page

func errorPageHTML(url: String, message: String) -> String {
    let escapedURL = url
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    let escapedMessage = message
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    return """
    <!doctype html><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body { margin:0; height:100vh; display:flex; align-items:center; justify-content:center;
             font: 14px -apple-system, system-ui, sans-serif;
             background:#f5f5f7; color:#1d1d1f; }
      @media (prefers-color-scheme: dark) { body { background:#1c1c1e; color:#f5f5f7; } }
      .box { max-width: 30rem; padding: 2rem; text-align:center; }
      h1 { font-size: 1.1rem; margin:0 0 .5rem; }
      p { margin:.4rem 0; opacity:.75; line-height:1.5; }
      code { font-size:.85em; word-break:break-all; opacity:.6; }
      a.btn { display:inline-block; margin-top:1.2rem; padding:.5rem 1.2rem; border-radius:8px;
              background:#0071e3; color:#fff; text-decoration:none; font-weight:500; }
    </style>
    <div class="box">
      <h1>Cannot open this page</h1>
      <p>\(escapedMessage)</p>
      <p><code>\(escapedURL)</code></p>
      <a class="btn" href="sgwebapp:retry">Retry</a>
    </div>
    """
}

// MARK: - Web policy (shared by the main window and every popup)

final class WebPolicyDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// Schemes WKWebView handles itself. Anything else belongs to another app.
    ///
    /// "javascript" is listed defensively: WebKit evaluates javascript: URLs
    /// internally without consulting this delegate, so href="javascript:void(0)"
    /// links work either way, but handing one to NSWorkspace on some future
    /// code path would be both broken and unwise.
    static let internalSchemes: Set<String> = ["http", "https", "about", "blob", "data", "file", "javascript"]

    /// Called when the user asks to retry after a load failure.
    var onRetry: ((WKWebView) -> Void)?
    /// Called after any successful page load, so freshly issued login cookies
    /// can be persisted without waiting for a clean quit.
    var onNavigationFinished: (() -> Void)?
    private var lastFailedURL: [ObjectIdentifier: String] = [:]

    // MARK: Navigation

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()

        if scheme == "sgwebapp" {
            decisionHandler(.cancel)
            if url.absoluteString.contains("retry") {
                if let target = lastFailedURL[ObjectIdentifier(webView)], let u = URL(string: target) {
                    webView.load(URLRequest(url: u))
                } else {
                    onRetry?(webView)
                }
            }
            return
        }

        // mailto:, tel:, zoommtg:, msteams:, itms-apps: ... hand off to the OS.
        if !WebPolicyDelegate.internalSchemes.contains(scheme) {
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onNavigationFinished?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(in: webView, error: error, url: webView.url?.absoluteString)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // The provisional URL is not on the web view yet; recover it from the error.
        let failing = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        showError(in: webView, error: error, url: failing?.absoluteString)
    }

    private func showError(in webView: WKWebView, error: Error, url: String?) {
        let ns = error as NSError
        // -999 is "another navigation superseded this one"; 102 is a scheme handoff
        // we performed ourselves. Neither is a failure the user should see.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 101) { return }

        let target = url ?? webView.url?.absoluteString ?? targetURLString
        lastFailedURL[ObjectIdentifier(webView)] = target
        webView.loadHTMLString(errorPageHTML(url: target, message: ns.localizedDescription), baseURL: nil)
    }

    // MARK: UI — popups

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // The configuration handed to us must be the one used, otherwise the new
        // web view is not in the opener's process/session and OAuth breaks.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = webView.customUserAgent ?? customUserAgent ?? resolveDefaultUserAgent()
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.allowsBackForwardNavigationGestures = true

        let controller = PopupWindowController(webView: popup, features: windowFeatures)
        controller.show()

        // A nil targetFrame means WebKit will not load the request itself.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            let scheme = (url.scheme ?? "").lowercased()
            if WebPolicyDelegate.internalSchemes.contains(scheme) {
                popup.load(navigationAction.request)
            }
        }
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let window = webView.window, !(window is FramelessWindow) {
            window.close()
        }
    }

    // MARK: UI — JS dialogs (silently ignored when unimplemented)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = appTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: webView.window ?? NSApp.keyWindow ?? NSWindow()) { _ in
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = appTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: webView.window ?? NSApp.keyWindow ?? NSWindow()) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = appTitle
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.beginSheetModal(for: webView.window ?? NSApp.keyWindow ?? NSWindow()) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    // MARK: UI — file uploads (<input type="file"> is inert without this)

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.begin { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: FramelessWindow!
    var webView: WKWebView!
    var borderView: BorderView!
    let policy = WebPolicyDelegate()
    var dataStore: WKWebsiteDataStore = .default()
    var exportTimer: Timer?
    var pendingExport: DispatchWorkItem?
    var autosaveName: NSWindow.FrameAutosaveName = "SGWebAppWindow"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let cleanName = (Bundle.main.bundleIdentifier ?? appTitle).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
        autosaveName = "SGWebAppWindow_" + (cleanName.isEmpty ? "default" : cleanName)

        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: windowWidth, height: windowHeight)
        let x = screenRect.origin.x + max(0, (screenRect.width - windowWidth) / 2)
        let y = screenRect.origin.y + max(0, (screenRect.height - windowHeight) / 2)
        let defaultFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        window = FramelessWindow(
            contentRect: defaultFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 400, height: 300)
        window.title = appTitle
        window.delegate = self

        if !explicitWindowSize {
            _ = window.setFrameAutosaveName(autosaveName)
            // Ensure restored window is visible on at least one currently active screen
            let isOnScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
            if !isOnScreen {
                let curSize = window.frame.size
                let sRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: curSize.width, height: curSize.height)
                let w = min(curSize.width, sRect.width)
                let h = min(curSize.height, sRect.height)
                let nx = sRect.origin.x + max(0, (sRect.width - w) / 2)
                let ny = sRect.origin.y + max(0, (sRect.height - h) / 2)
                window.setFrame(NSRect(x: nx, y: ny, width: w, height: h), display: true)
            }
        }

        borderView = BorderView(frame: NSRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height))
        borderView.autoresizingMask = [.width, .height]

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        // developerExtrasEnabled used to be set through private KVC, which raises
        // an uncatchable exception if WebKit ever renames the key.
        if #available(macOS 13.3, *) {
            // set on the web view below via isInspectable
        } else {
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        let totalInset = contentPadding > 0 ? contentPadding : borderWidth
        let webFrame = borderView.bounds.insetBy(dx: totalInset, dy: totalInset)
        webView = WKWebView(frame: webFrame, configuration: config)
        webView.customUserAgent = customUserAgent ?? resolveDefaultUserAgent()
        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.layer?.cornerRadius = max(0, cornerRadius - totalInset)
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        // drawsBackground is private KVC; guard it so a WebKit rename cannot crash us.
        if webView.responds(to: NSSelectorFromString("setDrawsBackground:")) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
        policy.onRetry = { wv in
            guard let url = URL(string: targetURLString) else { return }
            wv.load(URLRequest(url: url))
        }
        policy.onNavigationFinished = { [weak self] in
            self?.scheduleExport()
        }

        borderView.webView = webView
        borderView.addSubview(webView)
        borderView.updateBorder(width: borderWidth, radius: cornerRadius, padding: contentPadding, colorSpec: borderColorHex)

        let dragBarHeight: CGFloat = max(20.0, contentPadding > 0 ? contentPadding + 6.0 : 20.0)
        let dragBar = TopDraggableView(frame: NSRect(x: 0, y: borderView.bounds.height - dragBarHeight, width: borderView.bounds.width, height: dragBarHeight))
        dragBar.autoresizingMask = [.width, .minYMargin]
        borderView.addSubview(dragBar)

        window.contentView = borderView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        importCookies { [weak self] in
            self?.loadTargetURL()
        }

        // A quit handler alone is not enough: SIGTERM, a force quit or a crash
        // never runs it, and the login would be lost. Export shortly after each
        // page load as well, plus a slow periodic sweep for long-lived windows.
        exportTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.exportCookies(completion: nil)
        }
    }

    func loadTargetURL() {
        guard let url = URL(string: targetURLString) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        webView.load(request)
    }

    // MARK: Cookie import / export

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.sgwebapp.app.unknown"
    }

    /// Inject (a) any one-shot import produced by `sgwebapp import-cookies` and
    /// (b) the shared SSO jar, before the first page load.
    func importCookies(completion: @escaping () -> Void) {
        var incoming: [JarCookie] = []

        let pending = CookieStore.pendingURL(bundleID: bundleID)
        if let jar = CookieStore.load(pending) {
            incoming.append(contentsOf: jar.cookies)
            try? FileManager.default.removeItem(at: pending)
        }

        if shareLogin, let jar = CookieStore.load(CookieStore.jarURL) {
            incoming.append(contentsOf: jar.cookies.filter { domainMatches($0.domain, suffixes: sharedDomains) })
        }

        guard !incoming.isEmpty else {
            completion()
            return
        }

        let store = dataStore.httpCookieStore
        let group = DispatchGroup()
        for jc in incoming {
            guard let cookie = jc.toHTTPCookie() else { continue }
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        // Never let a stuck cookie store block startup: whichever of the two
        // fires first wins, and the latch keeps the page from loading twice.
        var finished = false
        let finishOnce = {
            assert(Thread.isMainThread)
            guard !finished else { return }
            finished = true
            completion()
        }
        group.notify(queue: .main, execute: finishOnce)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: finishOnce)
    }

    /// Coalesce the export that follows every navigation: a page load can fire
    /// several times in a row during a redirect chain.
    func scheduleExport() {
        guard shareLogin else { return }
        pendingExport?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.exportCookies(completion: nil) }
        pendingExport = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    /// Merge this app's SSO cookies back into the shared jar.
    func exportCookies(completion: (() -> Void)?) {
        guard shareLogin else { completion?(); return }
        dataStore.httpCookieStore.getAllCookies { cookies in
            let mine = cookies
                .filter { domainMatches($0.domain, suffixes: sharedDomains) }
                .compactMap { JarCookie($0) }
            guard !mine.isEmpty else { completion?(); return }

            var jar = CookieStore.load(CookieStore.jarURL) ?? CookieJar()
            var byKey = Dictionary(jar.cookies.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            for c in mine { byKey[c.key] = c }
            let now = Date().timeIntervalSince1970
            jar.cookies = byKey.values.filter { ($0.expires ?? .greatestFiniteMagnitude) > now }
                                      .sorted { $0.key < $1.key }
            CookieStore.save(jar, to: CookieStore.jarURL)
            completion?()
        }
    }

    // MARK: Menu

    func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appTitle)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit \(appTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        for (title, action, key) in [
            ("Reload", #selector(reloadPage), "r"),
            ("Back", #selector(goBack), "["),
            ("Forward", #selector(goForward), "]"),
        ] as [(String, Selector, String)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            viewMenu.addItem(item)
        }
        viewMenu.addItem(NSMenuItem.separator())
        for (title, action, key) in [
            ("Zoom In", #selector(zoomIn), "+"),
            ("Zoom Out", #selector(zoomOut), "-"),
            ("Actual Size", #selector(zoomReset), "0"),
        ] as [(String, Selector, String)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            viewMenu.addItem(item)
        }

        NSApp.mainMenu = mainMenu
    }

    @objc func reloadPage() { webView.reload() }
    @objc func goBack() { webView.goBack() }
    @objc func goForward() { webView.goForward() }
    @objc func zoomIn() { webView.pageZoom += 0.1 }
    @objc func zoomOut() { webView.pageZoom = max(0.2, webView.pageZoom - 0.1) }
    @objc func zoomReset() { webView.pageZoom = 1.0 }

    // MARK: - Window delegate (Frame Autosave)

    func windowDidMove(_ notification: Notification) {
        if !explicitWindowSize && window != nil {
            window.saveFrame(usingName: autosaveName)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if !explicitWindowSize && window != nil {
            window.saveFrame(usingName: autosaveName)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if !explicitWindowSize && window != nil {
            window.saveFrame(usingName: autosaveName)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !explicitWindowSize && window != nil {
            window.saveFrame(usingName: autosaveName)
        }
        guard shareLogin else { return .terminateNow }
        var replied = false
        let replyOnce = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        exportCookies { DispatchQueue.main.async(execute: replyOnce) }
        // Do not hang the quit if the cookie store is unresponsive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: replyOnce)
        return .terminateLater
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

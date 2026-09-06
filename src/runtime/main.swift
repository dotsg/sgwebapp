import Cocoa
import WebKit

// Parse hex color string to NSColor
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

// Reading global config file (~/.config/sgwebapp/config.json) if present
func readGlobalConfig() -> [String: Any] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let configFile = home.appendingPathComponent(".config/sgwebapp/config.json")
    guard let data = try? Data(contentsOf: configFile),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

// Parse color string or Tahoe dynamic glass appearance
func resolveBorderColor(_ colorSpec: String, appearance: NSAppearance?) -> CGColor {
    let clean = colorSpec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if clean == "tahoe" || clean == "auto" || clean == "system" {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            // Tahoe dark glass stroke: subtle luminous outline
            return NSColor(white: 1.0, alpha: 0.22).cgColor
        } else {
            // Tahoe light glass stroke: refined subtle dark outline
            return NSColor(white: 0.0, alpha: 0.16).cgColor
        }
    }
    return parseHexColor(clean).cgColor
}

let globalConfig = readGlobalConfig()

// Config variables with precedence: CLI args > Info.plist > config.json > Tahoe defaults
var targetURLString = Bundle.main.object(forInfoDictionaryKey: "SGWebAppURL") as? String ?? "https://example.com"
var appTitle = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Web App"
var borderColorHex = Bundle.main.object(forInfoDictionaryKey: "SGWebAppBorderColor") as? String
    ?? globalConfig["border_color"] as? String
    ?? "tahoe"

var borderWidth: CGFloat = {
    if let w = Bundle.main.object(forInfoDictionaryKey: "SGWebAppBorderWidth") as? Double { return CGFloat(w) }
    if let w = globalConfig["border_width"] as? Double { return CGFloat(w) }
    return 1.2
}()

var cornerRadius: CGFloat = {
    if let r = Bundle.main.object(forInfoDictionaryKey: "SGWebAppCornerRadius") as? Double { return CGFloat(r) }
    if let r = globalConfig["border_radius"] as? Double { return CGFloat(r) }
    return 18.0
}()

var contentPadding: CGFloat = {
    if let p = Bundle.main.object(forInfoDictionaryKey: "SGWebAppPadding") as? Double { return CGFloat(p) }
    if let p = globalConfig["padding"] as? Double { return CGFloat(p) }
    return 0.0
}()

var windowWidth: CGFloat = 1200
var windowHeight: CGFloat = 800

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
        if let val = args.first, let w = Double(val) { windowWidth = CGFloat(w); args = args.dropFirst() }
    case "--win-height":
        if let val = args.first, let h = Double(val) { windowHeight = CGFloat(h); args = args.dropFirst() }
    default:
        if targetURLString == "https://example.com" && arg.hasPrefix("http") {
            targetURLString = arg
        }
    }
}

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
    let shapeLayer = CAShapeLayer()
    let maskLayer = CAShapeLayer()
    let webMaskLayer = CAShapeLayer()
    let visualEffectView = NSVisualEffectView()
    weak var webView: WKWebView?
    var currentBorderWidth: CGFloat = 1.2
    var currentCornerRadius: CGFloat = 18.0
    var currentPadding: CGFloat = 0.0
    var colorSpec: String = "tahoe"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Tahoe Liquid Glass background material for padding areas
        visualEffectView.frame = bounds
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .windowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        addSubview(visualEffectView, positioned: .below, relativeTo: nil)

        shapeLayer.fillColor = nil
        shapeLayer.zPosition = 999 // Ensure border is always on top of web content
        layer?.addSublayer(shapeLayer)
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

        // 1. Hard-mask container view to Tahoe smooth squircle corner radius
        maskLayer.frame = bounds
        maskLayer.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        layer?.mask = maskLayer
        layer?.cornerRadius = radius
        layer?.masksToBounds = true

        // 2. Draw high-precision Tahoe glass stroke
        let inset = width / 2.0
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let strokeRadius = max(0, radius - inset)
        let path = CGPath(roundedRect: rect, cornerWidth: strokeRadius, cornerHeight: strokeRadius, transform: nil)

        shapeLayer.frame = bounds
        shapeLayer.path = path
        shapeLayer.lineWidth = width
        shapeLayer.strokeColor = resolvedColor

        // 3. Layout and mask inner webView with concentric corner radius
        let totalInset = width + padding
        if let wv = webView {
            wv.frame = bounds.insetBy(dx: totalInset, dy: totalInset)
            let innerRadius = max(0, radius - totalInset)
            if innerRadius > 0 {
                webMaskLayer.frame = wv.bounds
                webMaskLayer.path = CGPath(roundedRect: wv.bounds, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil)
                wv.layer?.mask = webMaskLayer
                wv.layer?.cornerRadius = innerRadius
                wv.layer?.masksToBounds = true
            } else {
                wv.layer?.mask = nil
                wv.layer?.cornerRadius = 0
            }
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

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: FramelessWindow!
    var webView: WKWebView!
    var borderView: BorderView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: windowWidth, height: windowHeight)
        let x = screenRect.origin.x + (screenRect.width - windowWidth) / 2
        let y = screenRect.origin.y + (screenRect.height - windowHeight) / 2
        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        window = FramelessWindow(
            contentRect: frame,
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

        // Outer container with rounded corners and border
        borderView = BorderView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        borderView.autoresizingMask = [.width, .height]

        // WebKit Configuration
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default() // persistent cookies & storage
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let totalInset = borderWidth + contentPadding
        let webFrame = borderView.bounds.insetBy(dx: totalInset, dy: totalInset)
        webView = WKWebView(frame: webFrame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.layer?.cornerRadius = max(0, cornerRadius - totalInset)
        webView.layer?.masksToBounds = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        borderView.webView = webView
        borderView.addSubview(webView)
        borderView.updateBorder(width: borderWidth, radius: cornerRadius, padding: contentPadding, colorSpec: borderColorHex)

        // Top drag handle bar (transparent, allows dragging without accidental text selection)
        let dragBarHeight: CGFloat = 20.0
        let dragBar = TopDraggableView(frame: NSRect(x: 0, y: borderView.bounds.height - dragBarHeight, width: borderView.bounds.width, height: dragBarHeight))
        dragBar.autoresizingMask = [.width, .minYMargin]
        borderView.addSubview(dragBar)

        window.contentView = borderView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let url = URL(string: targetURLString) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15.0
            webView.load(request)
        }
    }

    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appTitle)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit \(appTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit Menu (Copy/Paste/Cut support)
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

        // View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadPage), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)

        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)

        let zoomResetItem = NSMenuItem(title: "Actual Size", action: #selector(zoomReset), keyEquivalent: "0")
        zoomResetItem.target = self
        viewMenu.addItem(zoomResetItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func reloadPage() { webView.reload() }
    @objc func zoomIn() { webView.pageZoom += 0.1 }
    @objc func zoomOut() { webView.pageZoom = max(0.2, webView.pageZoom - 0.1) }
    @objc func zoomReset() { webView.pageZoom = 1.0 }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

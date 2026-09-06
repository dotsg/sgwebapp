import Cocoa
import CoreGraphics

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
            return NSColor(white: 1.0, alpha: 0.22).cgColor
        } else {
            return NSColor(white: 0.0, alpha: 0.18).cgColor
        }
    }
    return parseHexColor(clean).cgColor
}

let globalConfig = readGlobalConfig()

// Configuration arguments (defaults to macOS Tahoe Liquid Glass aesthetic)
var borderColorHex = globalConfig["border_color"] as? String ?? "tahoe"
var borderWidth: CGFloat = {
    if let w = globalConfig["border_width"] as? Double { return CGFloat(w) }
    if let n = globalConfig["border_width"] as? NSNumber { return CGFloat(n.doubleValue) }
    return 0.5
}()
var cornerRadius: CGFloat = {
    if let r = globalConfig["border_radius"] as? Double { return CGFloat(r) }
    if let n = globalConfig["border_radius"] as? NSNumber { return CGFloat(n.doubleValue) }
    return 26.0
}()
var targetAppNames: Set<String> = ["Google Chrome", "Brave Browser", "Microsoft Edge", "Chromium", "Arc"]
var matchAllApps = false

// Argument parsing
var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--color":
        if let val = args.first { borderColorHex = val; args = args.dropFirst() }
    case "--border-width", "--width":
        if let val = args.first, let w = Double(val) { borderWidth = CGFloat(w); args = args.dropFirst() }
    case "--border-radius", "--radius":
        if let val = args.first, let r = Double(val) { cornerRadius = CGFloat(r); args = args.dropFirst() }
    case "--all-apps":
        matchAllApps = true
    case "--app":
        if let val = args.first { targetAppNames.insert(val); args = args.dropFirst() }
    case "--help", "-h":
        print("""
        Usage: sgwebapp-border [options]
        Options:
          --color <hex|tahoe> Border color (hex e.g. 89b4fa, or 'tahoe' for dynamic glass, default: tahoe)
          --width <float>     Border width (default: 0.5)
          --radius <float>    Corner radius (default: 26.0)
          --all-apps          Show border on all active applications
          --app <name>        Add application name to match list
          --help, -h          Show this help message
        """)
        exit(0)
    default:
        break
    }
}

let borderColor = parseHexColor(borderColorHex)

class BorderView: NSView {
    var shapeLayer = CAShapeLayer()
    var currentRadius: CGFloat = 10.0
    var currentWidth: CGFloat = 2.5
    var currentColor: CGColor = NSColor.blue.cgColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.fillColor = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePath(radius: CGFloat, width: CGFloat, color: CGColor) {
        currentRadius = radius
        currentWidth = width
        currentColor = color

        let inset = width / 2.0
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        shapeLayer.path = path
        shapeLayer.lineWidth = width
        shapeLayer.strokeColor = color
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        updatePath(radius: currentRadius, width: currentWidth, color: currentColor)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var borderView: BorderView!
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        borderView = BorderView(frame: .zero)
        panel.contentView = borderView

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateBorder()
        }
    }

    func updateBorder() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            panel.orderOut(nil)
            return
        }

        let appName = frontApp.localizedName ?? ""
        if !matchAllApps && !targetAppNames.contains(appName) {
            if panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            panel.orderOut(nil)
            return
        }

        var foundWindowBounds: CGRect? = nil

        for win in windowList {
            let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? -1
            let layer = win[kCGWindowLayer as String] as? Int ?? -1
            if pid == frontApp.processIdentifier && layer == 0 {
                if let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat],
                   let w = boundsDict["Width"], let h = boundsDict["Height"],
                   let x = boundsDict["X"], let y = boundsDict["Y"],
                   w > 100 && h > 100 {
                    foundWindowBounds = CGRect(x: x, y: y, width: w, height: h)
                    break
                }
            }
        }

        guard let cgBounds = foundWindowBounds,
              let primaryScreen = NSScreen.screens.first else {
            if panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }

        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - (cgBounds.origin.y + cgBounds.height)
        let cocoaFrame = NSRect(x: cgBounds.origin.x, y: cocoaY, width: cgBounds.width, height: cgBounds.height)

        if panel.frame != cocoaFrame {
            panel.setFrame(cocoaFrame, display: true)
            let resolvedColor = resolveBorderColor(borderColorHex, appearance: NSApp.effectiveAppearance)
            borderView.updatePath(radius: cornerRadius, width: borderWidth, color: resolvedColor)
        }

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }
}

// Setup Signal Handlers
signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

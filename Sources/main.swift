import AppKit
import CoreText
import Foundation

// RocketToggle — 菜单栏一键开关 Shadowrocket（小火箭）

private enum C {
    static let name = "小火箭"
    static let serviceName = "Shadowrocket"
    static let appPaths = [
        "/Applications/Shadowrocket.app",
        NSHomeDirectory() + "/Applications/Shadowrocket.app",
    ]
}

private enum VPN {
    enum State: Equatable {
        case connected
        case connecting
        case disconnecting
        case disconnected
        case unknown(String)

        var isOn: Bool {
            switch self {
            case .connected, .connecting: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .connected: return "已连接"
            case .connecting: return "连接中…"
            case .disconnecting: return "断开中…"
            case .disconnected: return "已断开"
            case .unknown(let s): return s
            }
        }
    }

    static func status() -> State {
        let out = run("/usr/sbin/scutil", ["--nc", "status", C.serviceName])
        let first = out
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch first {
        case "Connected": return .connected
        case "Connecting": return .connecting
        case "Disconnecting": return .disconnecting
        case "Disconnected": return .disconnected
        case "": return .unknown("未找到 Shadowrocket")
        default:
            if first.localizedCaseInsensitiveContains("connected")
                && !first.localizedCaseInsensitiveContains("disconnected") {
                return .connected
            }
            return .unknown(first)
        }
    }

    static func connect() {
        _ = run("/usr/sbin/scutil", ["--nc", "start", C.serviceName])
    }

    static func disconnect() {
        _ = run("/usr/sbin/scutil", ["--nc", "stop", C.serviceName])
    }

    static func toggle() {
        switch status() {
        case .connected, .connecting:
            disconnect()
        default:
            connect()
        }
    }

    /// 已连或正在连则不再重复 start。
    static func ensureConnected() {
        switch status() {
        case .connected, .connecting:
            return
        default:
            connect()
        }
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private enum MenuIcon {
    private static let badge: CGFloat = 17.0
    private static let ringWidth: CGFloat = 1.45
    private static let ringColor = NSColor.white
    /// 连接：火箭橙
    private static let onColor = NSColor(srgbRed: 1.0, green: 0.48, blue: 0.12, alpha: 1)
    /// 断开：中灰
    private static let offColor = NSColor(calibratedWhite: 0.55, alpha: 1)
    /// 切换中：琥珀
    private static let busyColor = NSColor(srgbRed: 0.98, green: 0.78, blue: 0.18, alpha: 1)
    /// 未知：红
    private static let unknownColor = NSColor(srgbRed: 0.92, green: 0.28, blue: 0.28, alpha: 1)

    static func image(state: VPN.State) -> NSImage {
        let letter: NSColor
        switch state {
        case .connected: letter = onColor
        case .connecting, .disconnecting: letter = busyColor
        case .disconnected: letter = offColor
        case .unknown: letter = unknownColor
        }
        let d = badge
        let image = NSImage(size: NSSize(width: d, height: d))
        for scale in [1, 2, 3] as [CGFloat] {
            let px = Int((d * scale).rounded())
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: px,
                pixelsHigh: px,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }
            rep.size = NSSize(width: d, height: d)
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                ctx.imageInterpolation = .high
                ctx.shouldAntialias = true
                NSColor.clear.setFill()
                NSRect(x: 0, y: 0, width: d, height: d).fill()
                let badgeRect = NSRect(x: 0, y: 0, width: d, height: d)
                drawRing(color: ringColor, badgeRect: badgeRect)
                drawCentered(
                    "R",
                    font: timesBold(9),
                    color: letter,
                    center: NSPoint(x: d * 0.5, y: d * 0.5)
                )
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = false
        return image
    }

    private static func timesBold(_ size: CGFloat) -> NSFont {
        for name in ["TimesNewRomanPS-BoldMT", "Times New Roman Bold", "Times-Bold", "TimesNewRomanPSMT"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return .systemFont(ofSize: size, weight: .bold)
    }

    private static func drawRing(color: NSColor, badgeRect: NSRect) {
        let inset = ringWidth * 0.5 + 0.15
        let ring = NSBezierPath(ovalIn: badgeRect.insetBy(dx: inset, dy: inset))
        ring.lineWidth = ringWidth
        ring.lineCapStyle = .round
        ring.lineJoinStyle = .round
        color.setStroke()
        ring.stroke()
    }

    private static func glyphInk(_ s: String, font: NSFont) -> CGRect {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: [.font: font])
        )
        return CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    }

    private static func drawCentered(
        _ s: String,
        font: NSFont,
        color: NSColor,
        center: NSPoint
    ) {
        let ink = glyphInk(s, font: font)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// 只记你手动开/关的意图。休眠、关机导致的断开不算你关了。
private enum Intent {
    private static let key = "RocketToggle.wantConnected"
    static var wantConnected: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var pollTimer: Timer?
    private var lastState: VPN.State = .disconnected
    private var busy = false
    private var lastEnsureAt: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.imagePosition = .imageOnly
            btn.imageScaling = .scaleNone
            btn.target = self
            btn.action = #selector(clicked(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh(VPN.status(), animate: false)
        startPolling()
        observePowerEvents()
        if Intent.wantConnected {
            restoreConnection(after: 0.4)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func observePowerEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(powerResumed), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(powerResumed), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(powerResumed), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func powerResumed(_ note: Notification) {
        guard Intent.wantConnected else { return }
        restoreConnection(after: 1.2)
    }

    private func restoreConnection(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.ensureWantedConnection()
        }
    }

    private func ensureWantedConnection() {
        guard Intent.wantConnected, !busy else { return }
        let now = Date()
        if now.timeIntervalSince(lastEnsureAt) < 2 { return }
        lastEnsureAt = now
        DispatchQueue.global(qos: .userInitiated).async {
            VPN.ensureConnected()
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        let state = VPN.status()
        if state != lastState {
            lastState = state
            refresh(state, animate: true)
        }
        switch state {
        case .connected, .disconnected, .unknown:
            busy = false
        default:
            break
        }
        // 休眠/断网后系统会把 VPN 掐掉：若你没手动关，自动再连上。
        if Intent.wantConnected, !busy {
            switch state {
            case .disconnected, .unknown:
                ensureWantedConnection()
            default:
                break
            }
        }
    }

    @objc private func clicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            performToggle()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            showMenu()
            return
        }
        performToggle()
    }

    private func performToggle() {
        guard !busy else { return }
        busy = true
        let before = VPN.status()
        lastState = before
        let turningOff = before.isOn
        Intent.wantConnected = !turningOff
        refresh(turningOff ? .disconnecting : .connecting, animate: true)
        DispatchQueue.global(qos: .userInitiated).async {
            if turningOff {
                VPN.disconnect()
            } else {
                VPN.connect()
            }
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.2)
                let s = VPN.status()
                switch s {
                case .connected, .disconnected:
                    DispatchQueue.main.async {
                        self.lastState = s
                        self.busy = false
                        self.refresh(s, animate: true)
                    }
                    return
                default:
                    continue
                }
            }
            DispatchQueue.main.async {
                let s = VPN.status()
                self.lastState = s
                self.busy = false
                self.refresh(s, animate: true)
            }
        }
    }

    private func showMenu() {
        guard let button = item.button else { return }
        let state = VPN.status()
        let menu = NSMenu()
        let status = NSMenuItem(title: "状态：\(state.label)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: state.isOn ? "断开 \(C.name)" : "连接 \(C.name)",
            action: #selector(menuToggle),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let open = NSMenuItem(title: "打开 \(C.name)", action: #selector(openApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出菜单栏开关", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        let origin = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func menuToggle() {
        performToggle()
    }

    @objc private func openApp() {
        for path in C.appPaths where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
    }

    private func refresh(_ state: VPN.State, animate: Bool) {
        guard let button = item.button else { return }
        button.image = MenuIcon.image(state: state)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.toolTip = "\(C.name)：\(state.label)\n左键：连接/断开 · 右键：菜单\n休眠或开机后会按你上次的开关状态自动恢复"
        if animate {
            button.alphaValue = 0.55
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                button.animator().alphaValue = 1.0
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

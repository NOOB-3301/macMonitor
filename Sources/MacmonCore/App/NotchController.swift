import AppKit
import ApplicationServices

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

public final class NotchController {
    public private(set) var isVisible = false
    public var onChange: (() -> Void)?

    private var panel: NotchPanel?
    private var view: PanelView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var scanner: SessionScanner?
    private let thresholdStore = ThresholdStore()

    public init(scanner: SessionScanner? = nil) {
        self.scanner = scanner
    }

    public func start() {
        requestAccessibility()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] _ in
            self?.handleClick(at: NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] event in
            self?.handleLocalClick(event) ?? event
        }
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show(screen: NSScreen? = nil) {
        guard !isVisible else { return }
        let target = screen ?? NSScreen.builtIn
        guard let target else { return }
        setMode(.metrics, sessions: [])

        let size = PanelView.size
        let origin: NSPoint
        if let geometry = NotchGeometry.make(for: target) {
            origin = geometry.panelOrigin(size: size)
        } else {
            let visible = target.visibleFrame
            origin = NSPoint(x: visible.maxX - size.width - 8,
                             y: visible.maxY - size.height - 8)
        }

        let panel = makePanel()
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        self.panel = panel
        isVisible = true
        onChange?()
    }

    public func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel = nil
            self.view = nil
            self.isVisible = false
            if let observer = self.resignObserver {
                NotificationCenter.default.removeObserver(observer)
                self.resignObserver = nil
            }
            self.onChange?()
        }
    }

    public func currentThresholds() -> Thresholds {
        thresholdStore.current()
    }

    public func update(_ snapshot: Snapshot, _ claude: ClaudeUsage,
                       alerts: [AlertLine] = []) {
        guard isVisible, let view else { return }
        view.update(snapshot: snapshot, claude: claude,
                    alerts: alerts, thresholds: thresholdStore.current())
    }

    private func setMode(_ mode: PanelMode, sessions: [RunningSession]) {
        view?.setMode(mode, sessions: sessions)
    }

    private func handleAction(_ action: PanelView.PanelAction) {
        switch action {
        case .openSessions:
            setMode(.sessions, sessions: [])
            refreshSessions()
        case .openLimits:
            setMode(.limits, sessions: [])
        case .cycleLimit(let kind):
            _ = thresholdStore.cycle(kind)
        case .back:
            setMode(.metrics, sessions: [])
        case .focus(let pid):
            if let scanner {
                scanner.sessions { sessions in
                    guard let session = sessions.first(where: { $0.pid == pid }) else { return }
                    SessionFocus.focus(session)
                }
            }
            hide()
        case .quit:
            hide()
            NSApp.terminate(nil)
        }
    }

    private func refreshSessions() {
        guard let scanner else { return }
        scanner.sessions { [weak self] sessions in
            guard let self, self.isVisible,
                  self.view?.currentMode == .sessions else { return }
            self.setMode(.sessions, sessions: sessions)
        }
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: PanelView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        let effect = NSView(frame: NSRect(origin: .zero, size: PanelView.size))
        effect.wantsLayer = true
        effect.layer?.backgroundColor = NSColor(calibratedRed: 0.075,
                                                green: 0.085,
                                                blue: 0.105,
                                                alpha: 0.98).cgColor
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor

        let content = PanelView(frame: effect.bounds)
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        panel.contentView = effect

        view = content
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
        return panel
    }

    private func handleClick(at point: NSPoint) {
        if isVisible {
            if panel?.frame.contains(point) == true { return }
            hide()
            return
        }
        guard let screen = NSScreen.builtIn,
              let geometry = NotchGeometry.make(for: screen),
              geometry.triggerRect.contains(point) else {
            return
        }
        show(screen: screen)
    }

    private func handleLocalClick(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
        guard let view else { return event }
        if let panel, event.window === panel {
            let point = view.convert(event.locationInWindow, from: nil)
            if let action = view.action(at: point) {
                handleAction(action)
                return nil
            }
            return nil
        }
        if panel?.frame.contains(NSEvent.mouseLocation) == false {
            hide()
        }
        return event
    }

    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

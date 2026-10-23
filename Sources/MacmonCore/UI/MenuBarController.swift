import AppKit

public final class MenuBarController: NSObject, NSPopoverDelegate {
    public var onChange: (() -> Void)?

    private let popover = NSPopover()
    private let content = PanelViewController()
    private let thresholdStore = ThresholdStore()
    private let scanner: SessionScanner?

    public init(scanner: SessionScanner? = nil) {
        self.scanner = scanner
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = content
        popover.delegate = self
        content.onAction = { [weak self] action in
            self?.handle(action)
        }
    }

    public var isVisible: Bool { popover.isShown }

    public func toggle(from anchor: NSView?) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let anchor else { return }
        popover.show(relativeTo: anchor.bounds, of: anchor,
                     preferredEdge: .minY)
    }

    public func currentThresholds() -> Thresholds {
        thresholdStore.current()
    }

    public func update(_ snapshot: Snapshot, _ claude: ClaudeUsage,
                       alerts: [AlertLine] = []) {
        latestState = (snapshot, claude, alerts)
        guard popover.isShown else { return }
        content.update(snapshot: snapshot, claude: claude,
                       alerts: alerts, thresholds: thresholdStore.current())
    }

    private var latestState: (Snapshot, ClaudeUsage, [AlertLine]) = (Snapshot(), ClaudeUsage(), [])

    public func popoverDidShow(_ notification: Notification) {
        onChange?()
    }

    public func popoverDidClose(_ notification: Notification) {
        onChange?()
    }

    private func handle(_ action: PanelAction) {
        switch action {
        case .openSessions:
            content.setMode(.sessions, sessions: [])
            refreshSessions()
        case .openLimits:
            let state = latestState
            content.update(snapshot: state.0, claude: state.1,
                           alerts: state.2, thresholds: thresholdStore.current())
            content.setMode(.limits, sessions: [])
        case .cycleLimit(let kind):
            _ = thresholdStore.cycle(kind)
            let state = latestState
            content.update(snapshot: state.0, claude: state.1,
                           alerts: state.2, thresholds: thresholdStore.current())
        case .back:
            content.setMode(.metrics, sessions: [])
        case .focus(let pid):
            let scanner = self.scanner
            scanner?.sessions { sessions in
                guard let session = sessions.first(where: { $0.pid == pid }) else {
                    return
                }
                SessionFocus.focus(session)
            }
            hide()
        case .quit:
            hide()
            NSApp.terminate(nil)
        }
    }

    private func refreshSessions() {
        scanner?.sessions { [weak self] sessions in
            self?.content.setMode(.sessions, sessions: sessions)
        }
    }

    private func hide() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}

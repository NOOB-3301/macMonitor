import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let claude = ClaudeUsageService()
    private let scanner = SessionScanner()
    private let sampler = ProcessSampler()
    private var debouncer = AlertDebouncer()
    private let panel: MenuBarController

    public override init() {
        panel = MenuBarController(scanner: scanner)
        super.init()
    }

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lastSnapshot = Snapshot()
    private var lastTitle = ""
    private var panelVisible = false
    private var alertsActive = false
    private var interval: TimeInterval = 5

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        panel.onChange = { [weak self] in
            self?.panelVisibilityChanged()
        }

        claude.onChange = { [weak self] usage in
            self?.claudeChanged(usage)
        }

        _ = monitor.refresh()
        schedule(interval: 5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.claude.start()
        }

        if ProcessInfo.processInfo.environment["MACMON_DEMO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.panel.toggle(from: self?.statusItem?.button)
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWoke),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensSlept),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWoke),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "macmon"
        }
        statusItem = item
    }

    @objc private func togglePanel() {
        panel.toggle(from: statusItem?.button)
    }

    private func schedule(interval: TimeInterval) {
        self.interval = interval
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        lastSnapshot = monitor.refresh()
        claude.refreshIfDue()
        var alerts: [AlertLine] = []
        if panelVisible {
            let result = sampler.poll()
            let raw = AlertEngine.evaluate(lastSnapshot,
                                           thresholds: panel.currentThresholds(),
                                           cpuTop: result.cpuTop,
                                           memTop: result.memTop)
            alerts = debouncer.observe(raw)
        }
        alertsActive = !alerts.isEmpty
        updateStatusItem()
        if panelVisible {
            panel.update(lastSnapshot, claude.usage, alerts: alerts)
        }
    }

    private func panelVisibilityChanged() {
        panelVisible = panel.isVisible
        schedule(interval: panelVisible ? 2 : 5)
        if panelVisible {
            sampler.reset()
            lastSnapshot = monitor.refresh()
            panel.update(lastSnapshot, claude.usage, alerts: [])
        } else {
            sampler.reset()
            debouncer.reset()
        }
        updateStatusItem()
    }

    private func claudeChanged(_ usage: ClaudeUsage) {
        updateStatusItem()
        if panelVisible {
            panel.update(lastSnapshot, usage, alerts: [])
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        var title = Format.percent(lastSnapshot.cpu.total)
        if let peak = lastSnapshot.temperature.peak {
            title += " " + Format.temperature(peak)
        }
        if title != lastTitle {
            button.title = title
            lastTitle = title
        }

        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        if alertsActive {
            let dot = NSAttributedString(
                string: "● ",
                attributes: [.foregroundColor: NSColor.systemRed, .font: baseFont])
            let text = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.labelColor, .font: baseFont])
            button.attributedTitle = combine(dot, text)
        } else {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.labelColor, .font: baseFont])
        }

        var tooltip: [String] = []
        tooltip.append("CPU \(Format.percent(lastSnapshot.cpu.total))")
        tooltip.append("RAM \(Format.bytes(lastSnapshot.memory.used)) / \(Format.bytes(lastSnapshot.memory.total))")
        if lastSnapshot.gpu.available {
            tooltip.append("GPU \(Format.percent(lastSnapshot.gpu.utilization))")
        }
        if let claudeValue = claude.usage.fiveHour {
            tooltip.append("Claude 5h \(Format.percent(claudeValue))")
        }
        button.toolTip = tooltip.joined(separator: "  ·  ")
    }

    private func combine(_ first: NSAttributedString,
                         _ second: NSAttributedString) -> NSAttributedString {
        let combined = NSMutableAttributedString(attributedString: first)
        combined.append(second)
        return combined
    }

    @objc private func systemWoke() {
        monitor.reset()
        _ = monitor.refresh()
        schedule(interval: interval)
        claude.refreshIfDue()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.tick()
        }
    }

    @objc private func screensSlept() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func screensWoke() {
        monitor.reset()
        _ = monitor.refresh()
        schedule(interval: interval)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.tick()
        }
    }
}

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let claude = ClaudeUsageService()
    private let notch = NotchController()

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lastSnapshot = Snapshot()
    private var lastTitle = ""
    private var panelVisible = false
    private var interval: TimeInterval = 5

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        notch.onChange = { [weak self] in
            self?.panelVisibilityChanged()
        }
        notch.start()

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
                self?.notch.show()
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
        notch.toggle()
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
        updateStatusItem()
        if panelVisible {
            notch.update(lastSnapshot, claude.usage)
        }
    }

    private func panelVisibilityChanged() {
        panelVisible = notch.isVisible
        schedule(interval: panelVisible ? 2 : 5)
        if panelVisible {
            lastSnapshot = monitor.refresh()
            notch.update(lastSnapshot, claude.usage)
        }
        updateStatusItem()
    }

    private func claudeChanged(_ usage: ClaudeUsage) {
        updateStatusItem()
        if panelVisible {
            notch.update(lastSnapshot, usage)
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

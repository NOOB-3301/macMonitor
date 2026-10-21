import AppKit
import MacmonCore

if CommandLine.arguments.contains("--selftest") {
    exit(Int32(SelfCheck.run()))
}

if let index = CommandLine.arguments.firstIndex(of: "--render"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.appearance = NSAppearance(named: .darkAqua)

    let monitor = SystemMonitor()
    _ = monitor.refresh()
    Thread.sleep(forTimeInterval: 1.0)
    let snapshot = monitor.refresh()

    let claude = ClaudeUsage(
        fiveHour: 58,
        fiveHourReset: Date().addingTimeInterval(2 * 3600 + 14 * 60),
        sevenDay: 50,
        sevenDayReset: Date().addingTimeInterval(3 * 86400 + 4 * 3600),
        plan: "pro",
        fetchedAt: Date(),
        source: .api,
        stale: false
    )

    let view = PanelView(frame: NSRect(origin: .zero, size: PanelView.size))
    view.update(snapshot: snapshot, claude: claude)

    let container = NSView(frame: view.frame)
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
    container.addSubview(view)

    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = container
    window.orderBack(nil)
    container.layoutSubtreeIfNeeded()

    guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
        exit(1)
    }
    container.cacheDisplay(in: container.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    exit(0)
}

if CommandLine.arguments.contains("--geometry") {
    _ = NSApplication.shared
    for screen in NSScreen.screens {
        print("screen frame=\(screen.frame) visible=\(screen.visibleFrame) notch=\(screen.hasNotch) inset=\(screen.safeAreaInsets.top)")
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            print("  left=\(left) right=\(right)")
        }
        if let geometry = NotchGeometry.make(for: screen) {
            print("  notchRect=\(geometry.notchRect) trigger=\(geometry.triggerRect)")
            print("  panelOrigin=\(geometry.panelOrigin(size: PanelView.size))")
        }
    }
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    let monitor = SystemMonitor()
    _ = monitor.refresh()
    Thread.sleep(forTimeInterval: 1.0)
    let s = monitor.refresh()

    print("cpu total=\(String(format: "%.1f", s.cpu.total))% cores=\(s.cpu.perCore.count) load=\(String(format: "%.2f", s.cpu.load1))")
    print("mem used=\(Format.bytes(s.memory.used)) / \(Format.bytes(s.memory.total)) pressure=\(s.memory.pressure.label)")
    print("gpu available=\(s.gpu.available) util=\(String(format: "%.0f", s.gpu.utilization))%")
    print("net down=\(Format.rate(s.network.down)) up=\(Format.rate(s.network.up))")
    print("temp available=\(s.temperature.available) cpu=\(Format.temperature(s.temperature.cpu)) gpu=\(Format.temperature(s.temperature.gpu))")

    let claude = ClaudeUsageService()
    claude.onChange = { usage in
        print("claude source=\(usage.source.rawValue) stale=\(usage.stale) 5h=\(usage.fiveHour.map { String(format: "%.1f", $0) } ?? "-") 7d=\(usage.sevenDay.map { String(format: "%.1f", $0) } ?? "-") plan=\(usage.plan ?? "-") reason=\(usage.failureReason ?? "-")")
        exit(0)
    }
    claude.start()
    RunLoop.main.run(until: Date().addingTimeInterval(25))
    print("claude timeout")
    exit(1)
}

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

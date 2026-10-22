import AppKit
import MacmonCore

if CommandLine.arguments.contains("--selftest") {
    exit(Int32(SelfCheck.run()))
}

if CommandLine.arguments.contains("--render")
    || CommandLine.arguments.contains("--render-sessions") {
    let renderSessionMode = CommandLine.arguments.contains("--render-sessions")
    let flag = renderSessionMode ? "--render-sessions" : "--render"
    let index = CommandLine.arguments.firstIndex(of: flag)!
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
        stale: false,
        projection: UsageProjection.fiveHour(
            util: 58,
            resetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60),
            samples: [(53, Date().addingTimeInterval(-26 * 60)),
                      (58, Date())],
            now: Date()),
        weeklyText: UsageProjection.weeklyText(
            util: 50,
            resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600),
            now: Date())
    )

    var renderMode: PanelMode = renderSessionMode ? .sessions : .metrics
    var renderSessions: [RunningSession] = []
    if renderSessionMode {
        renderMode = .sessions
        renderSessions = [
            RunningSession(kind: .opencode, pid: 111, cwd: "/Users/arkab/Projects/macMonitor", tty: "ttys001",
                           sessionID: "ses_a", directory: "/Users/arkab/Projects/macMonitor", title: "macmon panel work"),
            RunningSession(kind: .claude, pid: 222, cwd: "/Users/arkab/Projects/LiveWallpaper", tty: "ttys003",
                           sessionID: nil, directory: nil, title: nil),
            RunningSession(kind: .claude, pid: 333, cwd: "/tmp", tty: "ttys005",
                           sessionID: "ses_b", directory: "/tmp", title: nil),
        ]
    }

    let view = PanelView(frame: NSRect(origin: .zero, size: PanelView.size))
    view.setMode(renderMode, sessions: renderSessions)
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

if CommandLine.arguments.contains("--sessions") {
    let scanner = SessionScanner()
    scanner.sessions { rows in
        for row in rows {
            let id = row.sessionID ?? "-"
            let title = row.title ?? "-"
            print("\(row.kind.rawValue) pid=\(row.pid) tty=\(row.tty) cwd=\(row.cwd) id=\(id) title=\(title)")
        }
        print("count=\(rows.count)")
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(10))
    print("timeout")
    exit(1)
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

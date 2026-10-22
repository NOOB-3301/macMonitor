import AppKit
import Foundation

public enum SelfCheck {
    private static var failures = 0

    public static func run() -> Int {
        failures = 0
        near("busy zero", Deltas.busyPercent(user: 0, system: 0, nice: 0, idle: 0), 0)
        near("busy half", Deltas.busyPercent(user: 50, system: 50, nice: 0, idle: 100), 50)
        near("busy full", Deltas.busyPercent(user: 10, system: 0, nice: 0, idle: 0), 100)
        near("wrap delta", Deltas.wrappingRate(current: 50, previous: 0xFFFF_FF00, elapsed: 1), 306)
        near("rate zero elapsed", Deltas.wrappingRate(current: 10, previous: 0, elapsed: 0), 0)

        equal("bytes zero", Format.bytes(0 as UInt64), "0 B")
        equal("bytes kb", Format.bytes(1024 as UInt64), "1.0 KB")
        equal("bytes gb", Format.bytes(UInt64(1024) * 1024 * 1024), "1.0 GB")
        equal("rate", Format.rate(1536), "1.5 KB/s")
        equal("temp nil", Format.temperature(nil), "--")
        equal("countdown now", Format.countdown(0), "now")
        equal("countdown hours", Format.countdown(3600), "1h 0m")
        equal("countdown days", Format.countdown(90000), "1d 1h")
        equal("percent", Format.percent(12.6), "13%")

        near("memory fraction", MemoryReading(used: 8, total: 16).fraction, 0.5)
        equal("pressure warning", MemoryPressure.from(2).label, "warning")
        equal("pressure unknown", MemoryPressure.from(99).label, "normal")

        let geometry = NotchGeometry(
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            notchRect: NSRect(x: 650, y: 868, width: 140, height: 32),
            triggerRect: NSRect(x: 646, y: 864, width: 148, height: 36)
        )
        let origin = geometry.panelOrigin(size: NSSize(width: 344, height: 336))
        near("panel centered", origin.x, 720 - 172)
        near("panel below notch", origin.y, 868 - 8 - 336)
        let tallOrigin = geometry.panelOrigin(size: PanelView.size)
        near("panel tall x", tallOrigin.x, 720 - PanelView.size.width / 2)
        near("panel tall y", tallOrigin.y, 868 - 8 - PanelView.size.height)

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let exhausted = UsageProjection.fiveHour(util: 100, resetsAt: resetsAt,
                                                 samples: [], now: now)
        equal("projection exhausted", exhausted.text, "exhausted · resets 1h 0m")
        if exhausted.role != .red {
            failures += 1
            print("FAIL projection exhausted role")
        }

        let runout = UsageProjection.fiveHour(util: 60,
                                              resetsAt: now.addingTimeInterval(600),
                                              samples: [(40, now.addingTimeInterval(-600)),
                                                        (60, now)],
                                              now: now)
        if !runout.text.hasPrefix("runout ~") {
            failures += 1
            print("FAIL projection runout text: \(runout.text)")
        }
        if runout.role != .orange {
            failures += 1
            print("FAIL projection runout role")
        }

        let idle = UsageProjection.fiveHour(util: 55,
                                            resetsAt: resetsAt,
                                            samples: [(55, now.addingTimeInterval(-1500)),
                                                      (55, now.addingTimeInterval(-1200))],
                                            now: now)
        equal("projection idle", idle.text, "idle · resets 1h 0m")
        if idle.role != .green {
            failures += 1
            print("FAIL projection idle role")
        }

        let onPace = UsageProjection.fiveHour(util: 20, resetsAt: resetsAt,
                                              samples: [], now: now)
        equal("projection on pace fallback", onPace.text, "on pace · resets 1h 0m")
        if onPace.role != .green {
            failures += 1
            print("FAIL projection on pace role")
        }
        let hotPace = UsageProjection.fiveHour(util: 60, resetsAt: resetsAt,
                                               samples: [(40, now.addingTimeInterval(-600)),
                                                         (60, now)],
                                               now: now)
        equal("projection hot pace", hotPace.text, "hot pace · throttle likely")
        if hotPace.role != .yellow {
            failures += 1
            print("FAIL projection hot pace role")
        }

        let weekly = UsageProjection.weeklyText(
            util: 52,
            resetsAt: Calendar.current.date(byAdding: .hour,
                                            value: 1, to: now),
            now: now) ?? ""
        if !weekly.hasPrefix("52% used · resets ") {
            failures += 1
            print("FAIL projection weekly: \(weekly)")
        }
        let weeklyNoReset = UsageProjection.weeklyText(util: 52, resetsAt: nil, now: now) ?? ""
        equal("projection weekly no reset", weeklyNoReset, "52% used")

        if Self.sessionIDParse("claude -s ses_abc123 --foo") != "ses_abc123" {
            failures += 1
            print("FAIL session id parse -s")
        }
        if Self.sessionIDParse("opencode --resume ses_def456") != "ses_def456" {
            failures += 1
            print("FAIL session id parse --resume")
        }
        if Self.sessionIDParse("claude --continue") != nil {
            failures += 1
            print("FAIL session id parse nil")
        }

        print(failures == 0 ? "selftest: ok" : "selftest: \(failures) failures")
        return failures == 0 ? 0 : 1
    }

    private static func sessionIDParse(_ argv: String) -> String? {
        SessionScanner.sessionID(in: argv)
    }

    private static func near(_ name: String, _ actual: Double, _ expected: Double,
                             tolerance: Double = 0.001) {
        if abs(actual - expected) > tolerance {
            failures += 1
            print("FAIL \(name): got \(actual), expected \(expected)")
        }
    }

    private static func equal(_ name: String, _ actual: String, _ expected: String) {
        if actual != expected {
            failures += 1
            print("FAIL \(name): got \(actual), expected \(expected)")
        }
    }
}

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

        print(failures == 0 ? "selftest: ok" : "selftest: \(failures) failures")
        return failures == 0 ? 0 : 1
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

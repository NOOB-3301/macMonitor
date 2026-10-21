import Foundation

public enum Format {
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    public static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = max(0, value)
        var unit = 0
        while amount >= 1024 && unit < units.count - 1 {
            amount /= 1024
            unit += 1
        }
        if unit == 0 {
            return "\(Int(amount)) \(units[unit])"
        }
        return String(format: amount >= 100 ? "%.0f %@" : "%.1f %@",
                      amount, units[unit])
    }

    public static func rate(_ value: Double) -> String {
        "\(bytes(value))/s"
    }

    public static func temperature(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f\u{00B0}", value)
    }

    public static func countdown(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "now" }
        let seconds = Int(interval)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func uptime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

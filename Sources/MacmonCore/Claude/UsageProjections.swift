import AppKit
import Foundation

public enum UsageProjection {
    public enum Role: Sendable {
        case green
        case yellow
        case orange
        case red
    }

    public struct FiveHour: Sendable {
        public let text: String
        public let role: Role

        public init(text: String, role: Role) {
            self.text = text
            self.role = role
        }
    }

    private static let hotPacePerHour: Double = 25

    public static func fiveHour(util: Double, resetsAt: Date,
                                samples: [(util: Double, at: Date)],
                                now: Date) -> FiveHour {
        let resetsIn = resetsAt.timeIntervalSince(now)

        if util >= 100 {
            return FiveHour(text: "exhausted · resets \(Format.countdown(resetsIn))",
                            role: .red)
        }

        if let pace = pace(from: samples, now: now) {
            if pace > 0.01 {
                let secondsToRunout = (100 - util) / pace * 3600

                if secondsToRunout >= resetsIn {
                    let slack = resetsIn
                    return FiveHour(
                        text: "runout ~\(Format.countdown(secondsToRunout)) · \(Format.countdown(slack)) before reset",
                        role: .orange
                    )
                }

                if pace > hotPacePerHour {
                    return FiveHour(text: "hot pace · throttle likely",
                                    role: .yellow)
                }
            } else if isIdle(samples: samples, now: now) {
                return FiveHour(text: "idle · resets \(Format.countdown(resetsIn))",
                                role: .green)
            }
        }

        if util >= 90 {
            return FiveHour(text: "near limit · resets \(Format.countdown(resetsIn))",
                            role: .orange)
        }

        return FiveHour(text: "on pace · resets \(Format.countdown(resetsIn))",
                        role: .green)
    }

    private static func pace(from samples: [(util: Double, at: Date)],
                             now: Date) -> Double? {
        let recent = samples.filter { now.timeIntervalSince($0.at) <= 1800 }
        guard recent.count >= 2 else { return nil }
        guard let first = recent.first, let last = recent.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span > 0 else { return nil }
        let delta = last.util - first.util
        if delta <= 0.01 {
            return 0
        }
        return delta / (span / 3600)
    }

    private static func isIdle(samples: [(util: Double, at: Date)],
                               now: Date) -> Bool {
        let recent = samples.filter { now.timeIntervalSince($0.at) <= 1800 }
        guard recent.count >= 2, let first = recent.first else { return false }
        return now.timeIntervalSince(first.at) >= 1200
    }

    public static func weeklyText(util: Double?, resetsAt: Date?,
                                  now: Date) -> String? {
        guard let util else { return nil }
        guard let resetsAt else {
            return String(format: "%.0f%% used", util)
        }
        return String(format: "%.0f%% used · resets %@", util, resetTime(resetsAt))
    }

    public static func resetTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat
            = DateFormatter.dateFormat(fromTemplate: "E h:mm a",
                                       options: 0, locale: Locale.current)
            ?? "EEE h:mm a"
        return formatter.string(from: date)
    }
}

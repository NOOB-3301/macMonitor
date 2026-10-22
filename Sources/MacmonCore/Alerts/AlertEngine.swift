import Foundation

public enum AlertSeverity: Int, Sendable {
    case orange = 1
    case red = 2
}

public struct AlertLine: Sendable, Equatable {
    public let metric: ThresholdKind
    public let text: String
    public let severity: AlertSeverity

    public init(metric: ThresholdKind, text: String, severity: AlertSeverity) {
        self.metric = metric
        self.text = text
        self.severity = severity
    }
}

public enum AlertEngine {
    public static func evaluate(_ snapshot: Snapshot,
                                thresholds: Thresholds,
                                cpuTop: [ProcessSample],
                                memTop: [ProcessSample]) -> [AlertLine] {
        var alerts: [AlertLine] = []

        if snapshot.cpu.total >= Double(thresholds.cpu) {
            let severity = snapshot.cpu.total >= 95 ? AlertSeverity.red : .orange
            let culprit = cpuTop.first { $0.utilization >= 10 }
            let text = culprit
                .map { "\($0.name) \(Format.percent($0.utilization))" }
                ?? "busy"
            alerts.append(AlertLine(metric: .cpu,
                                    text: "over ≥\(thresholds.cpu)% · \(text)",
                                    severity: severity))
        }

        let memPercent = snapshot.memory.fraction * 100
        if memPercent >= Double(thresholds.mem) {
            let severity = memPercent >= 95 ? AlertSeverity.red : .orange
            let culprit = memTop.first { $0.footprint >= 1_073_741_824 }
            let text = culprit
                .map { "\($0.name) \(Format.bytes($0.footprint))" }
                ?? "system-wide"
            alerts.append(AlertLine(metric: .mem,
                                    text: "over ≥\(thresholds.mem)% · \(text)",
                                    severity: severity))
        }

        if snapshot.gpu.available {
            if snapshot.gpu.utilization >= Double(thresholds.gpu) {
                let severity = snapshot.gpu.utilization >= 95
                    ? AlertSeverity.red : .orange
                alerts.append(AlertLine(
                    metric: .gpu,
                    text: "over ≥\(thresholds.gpu)% · busy",
                    severity: severity))
            }
        }

        return alerts
    }
}

public struct AlertDebouncer: Sendable {
    private var counters: [ThresholdKind: Int] = [:]

    public init() {}

    public mutating func observe(_ alerts: [AlertLine]) -> [AlertLine] {
        let raised = Set(alerts.map(\.metric))
        for kind in ThresholdKind.allCases {
            if raised.contains(kind) {
                counters[kind, default: 0] += 1
            } else {
                counters[kind] = 0
            }
        }
        var result: [AlertLine] = []
        for kind in raised where counters[kind, default: 0] >= 2 {
            if let alert = alerts.first(where: { $0.metric == kind }) {
                result.append(alert)
            }
        }
        return result
    }

    public mutating func reset() {
        counters.removeAll()
    }
}

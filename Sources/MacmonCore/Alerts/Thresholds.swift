import Foundation

public enum ThresholdKind: String, CaseIterable, Sendable {
    case cpu
    case mem
    case gpu
}

public struct Thresholds: Sendable, Equatable {
    public var cpu: Int
    public var mem: Int
    public var gpu: Int

    public init(cpu: Int = 85, mem: Int = 90, gpu: Int = 85) {
        self.cpu = cpu
        self.mem = mem
        self.gpu = gpu
    }

    public func percent(for kind: ThresholdKind) -> Int {
        switch kind {
        case .cpu: return cpu
        case .mem: return mem
        case .gpu: return gpu
        }
    }

    public mutating func cycle(_ kind: ThresholdKind) {
        let presets: [Int]
        var current: Int
        switch kind {
        case .cpu:
            presets = [70, 80, 85, 90, 95]
            current = cpu
        case .mem:
            presets = [80, 85, 90, 95]
            current = mem
        case .gpu:
            presets = [60, 70, 85, 95]
            current = gpu
        }
        let index = presets.firstIndex(of: current) ?? presets[0]
        let next = presets[(index + 1) % presets.count]
        switch kind {
        case .cpu: cpu = next
        case .mem: mem = next
        case .gpu: gpu = next
        }
    }
}

public struct PanelLimitsState: Sendable, Equatable {
    public var thresholds: Thresholds
    public var alerts: [AlertLine]

    public init(thresholds: Thresholds, alerts: [AlertLine] = []) {
        self.thresholds = thresholds
        self.alerts = alerts
    }
}

public final class ThresholdStore: @unchecked Sendable {
    public static let defaultThresholds = Thresholds()

    private let defaults: UserDefaults
    private var thresholds: Thresholds

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultValues = ThresholdStore.defaultThresholds
        let cpu = defaults.object(forKey: "threshold.cpu") as? Int
            ?? defaultValues.cpu
        let mem = defaults.object(forKey: "threshold.mem") as? Int
            ?? defaultValues.mem
        let gpu = defaults.object(forKey: "threshold.gpu") as? Int
            ?? defaultValues.gpu
        thresholds = Thresholds(cpu: cpu, mem: mem, gpu: gpu)
    }

    public func current() -> Thresholds {
        thresholds
    }

    public func cycle(_ kind: ThresholdKind) -> Thresholds {
        thresholds.cycle(kind)
        defaults.set(thresholds.cpu, forKey: "threshold.cpu")
        defaults.set(thresholds.mem, forKey: "threshold.mem")
        defaults.set(thresholds.gpu, forKey: "threshold.gpu")
        return thresholds
    }

    private func stored(_ key: String, _ defaults: UserDefaults) -> Int? {
        defaults.object(forKey: key) as? Int
    }
}

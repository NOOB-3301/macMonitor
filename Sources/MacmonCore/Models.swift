import Foundation

public struct CPUReading: Sendable {
    public var total: Double
    public var perCore: [Double]
    public var load1: Double
    public var load5: Double
    public var load15: Double

    public init(total: Double = 0, perCore: [Double] = [], load1: Double = 0,
                load5: Double = 0, load15: Double = 0) {
        self.total = total
        self.perCore = perCore
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
    }
}

public enum MemoryPressure: Int, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func from(_ raw: Int32) -> MemoryPressure {
        MemoryPressure(rawValue: Int(raw)) ?? .normal
    }

    public var label: String {
        switch self {
        case .normal: return "normal"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }
}

public struct MemoryReading: Sendable {
    public var used: UInt64
    public var total: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    public init(used: UInt64 = 0, total: UInt64 = 0, wired: UInt64 = 0,
                compressed: UInt64 = 0, cached: UInt64 = 0, swapUsed: UInt64 = 0,
                swapTotal: UInt64 = 0, pressure: MemoryPressure = .normal) {
        self.used = used
        self.total = total
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
    }

    public var fraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }
}

public struct GPUReading: Sendable {
    public var available: Bool
    public var utilization: Double
    public var renderer: Double
    public var memory: UInt64

    public init(available: Bool = false, utilization: Double = 0,
                renderer: Double = 0, memory: UInt64 = 0) {
        self.available = available
        self.utilization = utilization
        self.renderer = renderer
        self.memory = memory
    }
}

public struct NetworkInterfaceReading: Sendable {
    public var name: String
    public var down: Double
    public var up: Double

    public init(name: String, down: Double, up: Double) {
        self.name = name
        self.down = down
        self.up = up
    }
}

public struct NetworkReading: Sendable {
    public var down: Double
    public var up: Double
    public var interfaces: [NetworkInterfaceReading]

    public init(down: Double = 0, up: Double = 0,
                interfaces: [NetworkInterfaceReading] = []) {
        self.down = down
        self.up = up
        self.interfaces = interfaces
    }
}

public struct TemperatureReading: Sendable {
    public var cpu: Double?
    public var gpu: Double?
    public var peak: Double?
    public var available: Bool

    public init(cpu: Double? = nil, gpu: Double? = nil, peak: Double? = nil,
                available: Bool = false) {
        self.cpu = cpu
        self.gpu = gpu
        self.peak = peak
        self.available = available
    }
}

public struct Snapshot: Sendable {
    public var timestamp: Date
    public var cpu: CPUReading
    public var memory: MemoryReading
    public var gpu: GPUReading
    public var network: NetworkReading
    public var temperature: TemperatureReading

    public init(timestamp: Date = Date(), cpu: CPUReading = CPUReading(),
                memory: MemoryReading = MemoryReading(), gpu: GPUReading = GPUReading(),
                network: NetworkReading = NetworkReading(),
                temperature: TemperatureReading = TemperatureReading()) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.network = network
        self.temperature = temperature
    }
}

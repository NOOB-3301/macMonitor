import CShims
import Foundation

public final class SystemMonitor {
    private var previousCPU: [mm_cpu_ticks] = []
    private var previousNetwork: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousNetworkTime: Date?
    private var coreCount = 0

    public init() {}

    public func reset() {
        previousCPU = []
        previousNetwork = [:]
        previousNetworkTime = nil
    }

    public func refresh(now: Date = Date()) -> Snapshot {
        Snapshot(
            timestamp: now,
            cpu: readCPU(),
            memory: readMemory(),
            gpu: readGPU(),
            network: readNetwork(now: now),
            temperature: readTemperature()
        )
    }

    private func readCPU() -> CPUReading {
        var ticks = [mm_cpu_ticks](repeating: mm_cpu_ticks(), count: 34)
        let cores = Int(mm_cpu_read(&ticks, 33))
        coreCount = cores

        var perCore: [Double] = []
        var total = 0.0

        if cores > 0 && previousCPU.count == cores + 1 {
            perCore.reserveCapacity(cores)
            for index in 1...cores {
                let current = ticks[index]
                let previous = previousCPU[index]
                perCore.append(Deltas.busyPercent(
                    user: current.user &- previous.user,
                    system: current.system &- previous.system,
                    nice: current.nice &- previous.nice,
                    idle: current.idle &- previous.idle
                ))
            }
            let current = ticks[0]
            let previous = previousCPU[0]
            total = Deltas.busyPercent(
                user: current.user &- previous.user,
                system: current.system &- previous.system,
                nice: current.nice &- previous.nice,
                idle: current.idle &- previous.idle
            )
        }

        previousCPU = Array(ticks[0...max(0, cores)])

        var load1 = 0.0
        var load5 = 0.0
        var load15 = 0.0
        mm_load_avg(&load1, &load5, &load15)

        return CPUReading(total: total, perCore: perCore, load1: load1,
                          load5: load5, load15: load15)
    }

    private func readMemory() -> MemoryReading {
        var stats = mm_mem_stats()
        guard mm_mem_read(&stats) != 0 else { return MemoryReading() }
        return MemoryReading(
            used: stats.used,
            total: stats.total,
            wired: stats.wired,
            compressed: stats.compressed,
            cached: stats.cached,
            swapUsed: stats.swap_used,
            swapTotal: stats.swap_total,
            pressure: MemoryPressure.from(stats.pressure)
        )
    }

    private func readGPU() -> GPUReading {
        var stats = mm_gpu_stats()
        let ok = mm_gpu_read(&stats) != 0 && stats.valid != 0
        guard ok else { return GPUReading() }
        return GPUReading(
            available: true,
            utilization: stats.device,
            renderer: stats.renderer,
            memory: stats.in_use_sys_mem
        )
    }

    private func readNetwork(now: Date) -> NetworkReading {
        var raw = [mm_if_stats](repeating: mm_if_stats(), count: 16)
        let count = Int(mm_net_read(&raw, 16))
        let elapsed = previousNetworkTime.map { now.timeIntervalSince($0) } ?? 0

        var interfaces: [NetworkInterfaceReading] = []
        var totalDown = 0.0
        var totalUp = 0.0
        var current: [String: (rx: UInt64, tx: UInt64)] = [:]

        for index in 0..<count {
            let name = withUnsafeBytes(of: raw[index].name) { buffer -> String in
                guard let base = buffer.bindMemory(to: CChar.self).baseAddress else {
                    return ""
                }
                return String(cString: base)
            }
            guard !name.isEmpty else { continue }
            current[name] = (raw[index].rx, raw[index].tx)

            var down = 0.0
            var up = 0.0
            if let previous = previousNetwork[name] {
                down = Deltas.wrappingRate(current: raw[index].rx,
                                           previous: previous.rx, elapsed: elapsed)
                up = Deltas.wrappingRate(current: raw[index].tx,
                                         previous: previous.tx, elapsed: elapsed)
            }
            totalDown += down
            totalUp += up
            interfaces.append(NetworkInterfaceReading(name: name, down: down, up: up))
        }

        previousNetwork = current
        previousNetworkTime = now

        return NetworkReading(down: totalDown, up: totalUp,
                              interfaces: interfaces.sorted { $0.name < $1.name })
    }

    private func readTemperature() -> TemperatureReading {
        var sensors = [mm_temp_sensor](repeating: mm_temp_sensor(), count: 64)
        let count = Int(mm_temp_read(&sensors, 64))
        guard count > 0 else { return TemperatureReading() }

        var cpu: Double?
        var gpu: Double?
        var peak: Double?

        for index in 0..<count {
            let name = withUnsafeBytes(of: sensors[index].name) { buffer -> String in
                guard let base = buffer.bindMemory(to: CChar.self).baseAddress else {
                    return ""
                }
                return String(cString: base)
            }
            let value = sensors[index].celsius
            guard value > 1, value < 130 else { continue }

            if name.hasPrefix("Tp") {
                cpu = max(cpu ?? 0, value)
            } else if name.hasPrefix("Tg") {
                gpu = max(gpu ?? 0, value)
            }
            peak = max(peak ?? 0, value)
        }

        return TemperatureReading(cpu: cpu, gpu: gpu, peak: peak,
                                  available: peak != nil)
    }
}

import CShims
import Foundation

public struct ProcessSample: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let utilization: Double
    public let footprint: UInt64

    public init(pid: Int32, name: String, utilization: Double = 0,
                footprint: UInt64 = 0) {
        self.pid = pid
        self.name = name
        self.utilization = utilization
        self.footprint = footprint
    }
}

public struct ProcessPollResult: Sendable {
    public var cpuTop: [ProcessSample]
    public var memTop: [ProcessSample]

    public init(cpuTop: [ProcessSample] = [], memTop: [ProcessSample] = []) {
        self.cpuTop = cpuTop
        self.memTop = memTop
    }
}

public final class ProcessSampler: @unchecked Sendable {
    private struct Track {
        var lastMicros: UInt64
        var util: Double
    }

    private var tracks: [Int32: Track] = [:]
    private var previousTime: Date?
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    public init() {}

    public func reset() {
        tracks.removeAll()
        previousTime = nil
    }

    public func poll(now: Date = Date()) -> ProcessPollResult {
        let maxProcs = 2048
        var stats = [mm_proc_stat](repeating: mm_proc_stat(), count: maxProcs)
        var count = 0
        stats.withUnsafeMutableBufferPointer { buffer in
            count = max(Int(mm_top_procs(buffer.baseAddress, Int32(maxProcs))), 0)
        }
        guard count > 0, count < maxProcs else { return ProcessPollResult() }

        let present = Set(stats[0..<count].map(\.pid))
        tracks = tracks.filter { present.contains($0.key) }

        var elapsed = now.timeIntervalSince(previousTime ?? now)
        guard let previousTime, elapsed >= 1.0, elapsed <= 3600 else {
            self.previousTime = now
            for entry in stats[0..<count] where entry.pid != selfPID {
                tracks[entry.pid] = Track(lastMicros: entry.cpu_micros, util: 0)
            }
            return ProcessPollResult()
        }
        self.previousTime = now
        elapsed = max(elapsed, 1.0)

        var cpuCandidates: [(pid: Int32, util: Double)] = []
        for entry in stats[0..<count] {
            guard entry.pid != selfPID else { continue }
            let delta: UInt64
            if let track = tracks[entry.pid] {
                delta = entry.cpu_micros > track.lastMicros
                    ? entry.cpu_micros - track.lastMicros : 0
            } else {
                delta = 0
            }
            let raw = Self.utilizationPercent(deltaMicros: delta, elapsed: elapsed)
            let smoothed = tracks[entry.pid].map { $0.util * 0.35 + raw * 0.65 } ?? raw
            tracks[entry.pid] = Track(lastMicros: entry.cpu_micros, util: smoothed)
            if smoothed >= 1.0 {
                cpuCandidates.append((entry.pid, smoothed))
            }
        }

        var cpuTop: [ProcessSample] = []
        cpuCandidates.sort { $0.util > $1.util }
        for candidate in cpuCandidates.prefix(3) {
            cpuTop.append(ProcessSample(pid: candidate.pid,
                                        name: resolveName(candidate.pid),
                                        utilization: candidate.util))
        }

        let byMem = stats[0..<count]
            .filter { $0.pid != selfPID && $0.footprint >= 1_048_576 }
            .sorted { $0.footprint > $1.footprint }
        var memTop: [ProcessSample] = []
        for entry in byMem.prefix(3) {
            memTop.append(ProcessSample(pid: entry.pid, name: resolveName(entry.pid),
                                        footprint: entry.footprint))
        }

        return ProcessPollResult(cpuTop: cpuTop, memTop: memTop)
    }

    public static func utilizationPercent(deltaMicros: UInt64, elapsed: Double) -> Double {
        min(Double(deltaMicros) / (max(elapsed, 1.0) * 1_000_000) * 100, 800)
    }

    private func resolveName(_ pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: 1024)
        let length = path.withUnsafeMutableBufferPointer { buffer -> Int32 in
            mm_proc_path(pid, buffer.baseAddress, Int32(buffer.count))
        }
        guard length > 0 else { return "system" }
        return (String(cString: path) as NSString).lastPathComponent
    }
}

import Foundation

public enum Deltas {
    public static func busyPercent(user: UInt64, system: UInt64, nice: UInt64,
                                   idle: UInt64) -> Double {
        let total = user &+ system &+ nice &+ idle
        guard total > 0 else { return 0 }
        let busy = user &+ system &+ nice
        return min(100, max(0, Double(busy) / Double(total) * 100))
    }

    public static func wrappingRate(current: UInt64, previous: UInt64,
                                    elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        let c = UInt32(truncatingIfNeeded: current)
        let p = UInt32(truncatingIfNeeded: previous)
        let delta = c &- p
        return Double(delta) / elapsed
    }
}

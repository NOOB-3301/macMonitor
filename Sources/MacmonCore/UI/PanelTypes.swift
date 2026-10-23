import Foundation

public enum PanelMode: Equatable {
    case metrics
    case sessions
    case limits
}

public enum PanelAction: Equatable {
    case openSessions
    case openLimits
    case back
    case cycleLimit(ThresholdKind)
    case focus(pid: Int32)
    case quit
}

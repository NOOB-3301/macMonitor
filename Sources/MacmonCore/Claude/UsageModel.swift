import Foundation

public struct ClaudeUsage: Sendable {
    public enum Source: String, Sendable {
        case api
        case cache
        case local
        case none
    }

    public var fiveHour: Double?
    public var fiveHourReset: Date?
    public var sevenDay: Double?
    public var sevenDayReset: Date?
    public var opus: Double?
    public var sonnet: Double?
    public var extraUsed: Double?
    public var extraLimit: Double?
    public var plan: String?
    public var fetchedAt: Date?
    public var source: Source
    public var stale: Bool
    public var localTokens: Int?
    public var failureReason: String?
    public var projection: UsageProjection.FiveHour?
    public var weeklyText: String?

    public init(fiveHour: Double? = nil, fiveHourReset: Date? = nil,
                sevenDay: Double? = nil, sevenDayReset: Date? = nil,
                opus: Double? = nil, sonnet: Double? = nil,
                extraUsed: Double? = nil, extraLimit: Double? = nil,
                plan: String? = nil, fetchedAt: Date? = nil,
                source: Source = .none, stale: Bool = true,
                localTokens: Int? = nil, failureReason: String? = nil,
                projection: UsageProjection.FiveHour? = nil,
                weeklyText: String? = nil) {
        self.fiveHour = fiveHour
        self.fiveHourReset = fiveHourReset
        self.sevenDay = sevenDay
        self.sevenDayReset = sevenDayReset
        self.opus = opus
        self.sonnet = sonnet
        self.extraUsed = extraUsed
        self.extraLimit = extraLimit
        self.plan = plan
        self.fetchedAt = fetchedAt
        self.source = source
        self.stale = stale
        self.localTokens = localTokens
        self.failureReason = failureReason
        self.projection = projection
        self.weeklyText = weeklyText
    }

    public var hasData: Bool {
        fiveHour != nil || sevenDay != nil
    }
}

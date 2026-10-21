import Foundation

public final class ClaudeUsageService {
    public private(set) var usage: ClaudeUsage
    public var onChange: ((ClaudeUsage) -> Void)?

    private let session: URLSession
    private var credentials: ClaudeCredentials?
    private var credentialsLoadedAt: Date?
    private var nextAttempt = Date.distantPast
    private var failures = 0
    private var fetching = false
    private var estimating = false
    private var loadingCredentials = false

    private let pollInterval: TimeInterval = 300
    private let staleInterval: TimeInterval = 600

    private struct Cached: Codable {
        var fiveHour: Double?
        var fiveHourReset: Date?
        var sevenDay: Double?
        var sevenDayReset: Date?
        var opus: Double?
        var sonnet: Double?
        var extraUsed: Double?
        var extraLimit: Double?
        var plan: String?
        var fetchedAt: Date?
    }

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
        usage = Self.loadCache() ?? ClaudeUsage()
    }

    public func start() {
        nextAttempt = .distantPast
        refreshIfDue()
        if !usage.hasData {
            estimateLocal()
        }
    }

    public func refreshIfDue(now: Date = Date()) {
        guard now >= nextAttempt, !fetching else { return }
        guard let credentials = cachedCredentials(now: now) else {
            nextAttempt = now.addingTimeInterval(5)
            loadCredentialsAsync()
            return
        }
        if credentials.isExpired {
            usage.stale = true
            usage.source = usage.hasData ? .cache : .local
            usage.failureReason = "Claude Code token expired"
            if let subscription = credentials.subscriptionType {
                usage.plan = subscription
            }
            deliver()
            nextAttempt = now.addingTimeInterval(1800)
            estimateLocal()
            return
        }

        if usage.plan == nil {
            usage.plan = credentials.subscriptionType
        }

        fetching = true
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)",
                         forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handle(data: data, response: response, error: error)
            }
        }
        task.resume()
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?) {
        fetching = false
        let now = Date()

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                if let data, applyResponse(data, now: now) {
                    failures = 0
                    usage.stale = false
                    usage.failureReason = nil
                    usage.source = .api
                    usage.fetchedAt = now
                    usage.localTokens = nil
                    saveCache()
                    deliver()
                    nextAttempt = now.addingTimeInterval(pollInterval)
                    return
                }
                scheduleFailure(reason: "Unreadable usage response", now: now, base: 600)
            case 401, 403:
                scheduleFailure(reason: "Claude session expired", now: now, base: 1800)
            case 429:
                scheduleFailure(reason: "Usage endpoint rate limited", now: now, base: 900)
            default:
                scheduleFailure(reason: "Usage endpoint HTTP \(http.statusCode)", now: now, base: 300)
            }
            return
        }

        if let error {
            scheduleFailure(reason: error.localizedDescription, now: now, base: 300)
        } else {
            scheduleFailure(reason: "No response", now: now, base: 300)
        }
    }

    private func scheduleFailure(reason: String, now: Date, base: TimeInterval) {
        failures = min(failures + 1, 4)
        let delay = min(3600, base * pow(2, Double(failures - 1)))
        nextAttempt = now.addingTimeInterval(delay)
        usage.stale = true
        usage.source = usage.hasData ? .cache : .local
        usage.failureReason = reason
        deliver()
        if !usage.hasData || now.timeIntervalSince(usage.fetchedAt ?? .distantPast) > 1800 {
            estimateLocal()
        }
    }

    private func applyResponse(_ data: Data, now: Date) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        var updated = usage
        let five = root["five_hour"] as? [String: Any]
        let seven = root["seven_day"] as? [String: Any]
        let opus = root["seven_day_opus"] as? [String: Any]
        let sonnet = root["seven_day_sonnet"] as? [String: Any]

        updated.fiveHour = number(five?["utilization"])
        updated.fiveHourReset = date(five?["resets_at"])
        updated.sevenDay = number(seven?["utilization"])
        updated.sevenDayReset = date(seven?["resets_at"])
        updated.opus = number(opus?["utilization"])
        updated.sonnet = number(sonnet?["utilization"])

        if let extra = root["extra_usage"] as? [String: Any] {
            updated.extraUsed = number(extra["used_credits"])
            updated.extraLimit = number(extra["monthly_limit"])
        }

        guard updated.fiveHour != nil || updated.sevenDay != nil else {
            return false
        }
        updated.fetchedAt = now
        usage = updated
        return true
    }

    private func estimateLocal() {
        guard !estimating else { return }
        estimating = true
        LocalUsageEstimator.estimateTokens { [weak self] tokens in
            DispatchQueue.main.async {
                guard let self else { return }
                self.estimating = false
                self.usage.localTokens = tokens
                if !self.usage.hasData {
                    self.usage.source = .local
                }
                self.deliver()
            }
        }
    }

    private func cachedCredentials(now: Date) -> ClaudeCredentials? {
        if let credentials, let loadedAt = credentialsLoadedAt,
           now.timeIntervalSince(loadedAt) < 600 {
            return credentials
        }
        return nil
    }

    private func loadCredentialsAsync() {
        guard !loadingCredentials else { return }
        loadingCredentials = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let loaded = ClaudeKeychain.loadCredentials()
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingCredentials = false
                if let loaded {
                    self.credentials = loaded
                    self.credentialsLoadedAt = Date()
                    self.nextAttempt = .distantPast
                    self.refreshIfDue()
                } else {
                    self.usage.stale = true
                    self.usage.source = self.usage.hasData ? .cache : .local
                    self.usage.failureReason = "Claude Code credentials not found"
                    self.deliver()
                    self.nextAttempt = Date().addingTimeInterval(1800)
                    self.estimateLocal()
                }
            }
        }
    }

    private func deliver() {
        usage.stale = usage.stale || {
            guard let fetchedAt = usage.fetchedAt else { return true }
            return Date().timeIntervalSince(fetchedAt) > staleInterval
        }()
        onChange?(usage)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter.macmon.date(from: string)
            ?? ISO8601DateFormatter.macmonNoFraction.date(from: string)
    }

    private static func loadCache() -> ClaudeUsage? {
        guard let data = try? Data(contentsOf: Paths.claudeCache),
              let cached = try? JSONDecoder().decode(Cached.self, from: data) else {
            return nil
        }
        var usage = ClaudeUsage()
        usage.fiveHour = cached.fiveHour
        usage.fiveHourReset = cached.fiveHourReset
        usage.sevenDay = cached.sevenDay
        usage.sevenDayReset = cached.sevenDayReset
        usage.opus = cached.opus
        usage.sonnet = cached.sonnet
        usage.extraUsed = cached.extraUsed
        usage.extraLimit = cached.extraLimit
        usage.plan = cached.plan
        usage.fetchedAt = cached.fetchedAt
        usage.source = .cache
        usage.stale = true
        return usage
    }

    private func saveCache() {
        let cached = Cached(
            fiveHour: usage.fiveHour,
            fiveHourReset: usage.fiveHourReset,
            sevenDay: usage.sevenDay,
            sevenDayReset: usage.sevenDayReset,
            opus: usage.opus,
            sonnet: usage.sonnet,
            extraUsed: usage.extraUsed,
            extraLimit: usage.extraLimit,
            plan: usage.plan,
            fetchedAt: usage.fetchedAt
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: Paths.claudeCache, options: .atomic)
    }
}

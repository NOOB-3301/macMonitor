import AppKit

public final class PanelViewController: NSViewController {
    public var onAction: ((PanelAction) -> Void)?

    private var snapshot = Snapshot()
    private var claude = ClaudeUsage()
    private var alerts: [AlertLine] = []
    private var thresholds = Thresholds()
    private var sessions: [RunningSession] = []
    private var mode: PanelMode = .metrics

    private var rootStack: NSStackView?
    private var metricsPage: NSStackView?
    private var sessionsPage: NSStackView?
    private var limitsPage: NSStackView?

    private var metricRows: [MetricRowView] = []
    private var systemCard: GlassCard?
    private var claudeCard: GlassCard?
    private var claudeStatusField: NSTextField?
    private var claudeRows: [ClaudeWindowRow] = []
    private var claudeExtraField: NSTextField?

    private var sessionsEmptyField: NSTextField?
    private var sessionListStack: NSStackView?
    private var sessionsMoreField: NSTextField?

    private var limitRows: [LimitRowView] = []
    private var limitsAlertsStack: NSStackView?

    private var footerContainer: NSStackView?
    private var footerMetricsButtons: [HoverRow] = []
    private var footerHintField: NSTextField?

    private var cardWidth: CGFloat {
        Theme.panelSize.width - Theme.paddingPanel * 2
    }

    private var cardInnerWidth: CGFloat {
        cardWidth - Theme.paddingCard * 2
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Theme.panelSize))
        view = root
        buildLayout()
        preferredContentSize = Theme.panelSize
    }

    public func setMode(_ mode: PanelMode, sessions: [RunningSession]) {
        self.mode = mode
        self.sessions = sessions
        refreshMode()
    }

    public func update(snapshot: Snapshot, claude: ClaudeUsage,
                       alerts: [AlertLine] = [], thresholds: Thresholds? = nil) {
        self.snapshot = snapshot
        self.claude = claude
        self.alerts = alerts
        if let thresholds {
            self.thresholds = thresholds
        }
        refreshContent()
    }

    // MARK: - Construction

    private func buildLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .gravityAreas
        root.spacing = Theme.spacingGroup
        root.edgeInsets = NSEdgeInsets(
            top: Theme.paddingPanel, left: Theme.paddingPanel,
            bottom: Theme.paddingPanel, right: Theme.paddingPanel)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        rootStack = root

        let metrics = NSStackView()
        metrics.orientation = .vertical
        metrics.alignment = .leading
        metrics.spacing = Theme.spacingStack
        let sessions = NSStackView()
        sessions.orientation = .vertical
        sessions.alignment = .leading
        sessions.spacing = Theme.spacingStack
        let limits = NSStackView()
        limits.orientation = .vertical
        limits.alignment = .leading
        limits.spacing = Theme.spacingStack
        for page in [metrics, sessions, limits] {
            page.translatesAutoresizingMaskIntoConstraints = false
            root.addArrangedSubview(page)
        }
        metricsPage = metrics
        sessionsPage = sessions
        limitsPage = limits

        buildMetricsPage(into: metrics)
        buildSessionsPage(into: sessions)
        buildLimitsPage(into: limits)
        buildFooter(onto: root)
        refreshMode()
    }

    private func buildMetricsPage(into page: NSStackView) {
        let systemCard = GlassCard(frame: .zero)
        systemCard.translatesAutoresizingMaskIntoConstraints = false
        systemCard.widthAnchor.constraint(
            equalToConstant: cardWidth).isActive = true
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = Theme.spacingStack
        inner.edgeInsets = NSEdgeInsets(
            top: Theme.paddingCard, left: Theme.paddingCard,
            bottom: Theme.paddingCard, right: Theme.paddingCard)
        inner.translatesAutoresizingMaskIntoConstraints = false
        systemCard.content.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: systemCard.content.topAnchor),
            inner.leadingAnchor.constraint(equalTo: systemCard.content.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: systemCard.content.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: systemCard.content.bottomAnchor),
        ])

        let cpu = MetricRowView(title: "CPU", includesBar: true)
        let mem = MetricRowView(title: "MEMORY", includesBar: true)
        let gpu = MetricRowView(title: "GPU", includesBar: true)
        let net = MetricRowView(title: "NETWORK", includesBar: false)
        let temp = MetricRowView(title: "TEMPERATURE", includesBar: false)
        metricRows = [cpu, mem, gpu, net, temp]
        for row in metricRows {
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalToConstant: cardInnerWidth),
            ])
            inner.addArrangedSubview(row)
        }

        self.systemCard = systemCard
        page.addArrangedSubview(systemCard)

        let claude = GlassCard(frame: .zero)
        claude.translatesAutoresizingMaskIntoConstraints = false
        claude.widthAnchor.constraint(
            equalToConstant: cardWidth).isActive = true
        let claudeInner = NSStackView()
        claudeInner.orientation = .vertical
        claudeInner.alignment = .leading
        claudeInner.spacing = Theme.spacingStack
        claudeInner.edgeInsets = NSEdgeInsets(
            top: Theme.paddingCard, left: Theme.paddingCard,
            bottom: Theme.paddingCard, right: Theme.paddingCard)
        claudeInner.translatesAutoresizingMaskIntoConstraints = false
        claude.content.addSubview(claudeInner)
        NSLayoutConstraint.activate([
            claudeInner.topAnchor.constraint(equalTo: claude.content.topAnchor),
            claudeInner.leadingAnchor.constraint(equalTo: claude.content.leadingAnchor),
            claudeInner.trailingAnchor.constraint(equalTo: claude.content.trailingAnchor),
            claudeInner.bottomAnchor.constraint(equalTo: claude.content.bottomAnchor),
        ])

        let status = makeLabel("", font: .tag, color: .secondary, align: .right)
        claudeStatusField = status
        let header = NSStackView()
        header.orientation = .horizontal
        header.addArrangedSubview(makeLabel("CLAUDE", font: .tag, color: .secondary))
        header.addArrangedSubview(makeSpacer())
        header.addArrangedSubview(status)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalToConstant: cardInnerWidth),
        ])
        claudeInner.addArrangedSubview(header)

        let five = ClaudeWindowRow(title: "5 hour")
        let weekly = ClaudeWindowRow(title: "weekly")
        claudeRows = [five, weekly]
        for row in claudeRows {
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalToConstant: cardInnerWidth),
            ])
            claudeInner.addArrangedSubview(row)
        }

        let extra = makeLabel("", font: .detail, color: .tertiary)
        claudeExtraField = extra
        extra.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            extra.widthAnchor.constraint(equalToConstant: cardInnerWidth),
        ])
        claudeInner.addArrangedSubview(extra)

        self.claudeCard = claude
        page.addArrangedSubview(claude)
    }

    private func buildSessionsPage(into page: NSStackView) {
        let back = makeBackBar("SESSIONS")
        back.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        page.addArrangedSubview(back)

        let empty = makeLabel("no sessions running", font: .detail, color: .tertiary)
        empty.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            empty.widthAnchor.constraint(equalToConstant: cardInnerWidth),
        ])
        sessionsEmptyField = empty
        page.addArrangedSubview(empty)

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        list.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        sessionListStack = list
        page.addArrangedSubview(list)

        let more = makeLabel("", font: .detail, color: .tertiary)
        more.translatesAutoresizingMaskIntoConstraints = false
        sessionsMoreField = more
        page.addArrangedSubview(more)
    }

    private func buildLimitsPage(into page: NSStackView) {
        let back = makeBackBar("LIMITS")
        back.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        page.addArrangedSubview(back)

        page.addArrangedSubview(
            makeLabel("alert when metric exceeds", font: .detail, color: .tertiary))

        let alertStack = NSStackView()
        alertStack.orientation = .vertical
        alertStack.alignment = .leading
        alertStack.spacing = 2
        limitsAlertsStack = alertStack
        page.addArrangedSubview(alertStack)

        let rows = [
            LimitRowView(kind: .cpu, note: "load per core · presets 70–95%",
                         width: cardWidth),
            LimitRowView(kind: .mem, note: "used / total RAM · presets 80–95%",
                         width: cardWidth),
            LimitRowView(kind: .gpu, note: "utilization · presets 60–95%",
                         width: cardWidth),
        ]
        limitRows = rows
        for row in rows {
            row.hostAction = self
            page.addArrangedSubview(row)
        }
    }

    private func buildFooter(onto root: NSStackView) {
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = Theme.spacingStack
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        footerContainer = footer

        let sessionsButton = makeFooterButton("Sessions", symbol: "terminal") {
            [weak self] in self?.onAction?(.openSessions)
        }
        let limitsButton = makeFooterButton("Limits", symbol: "gauge") {
            [weak self] in self?.onAction?(.openLimits)
        }
        let quitButton = makeFooterButton("Quit", symbol: "xmark") {
            [weak self] in self?.onAction?(.quit)
        }
        let hint = makeLabel("", font: .detail, color: .tertiary)
        footerHintField = hint
        footerMetricsButtons = [sessionsButton, limitsButton]
        footer.addArrangedSubview(sessionsButton)
        footer.addArrangedSubview(limitsButton)
        footer.addArrangedSubview(makeSpacer())
        footer.addArrangedSubview(hint)
        footer.addArrangedSubview(makeSpacer())
        footer.addArrangedSubview(quitButton)

        root.addArrangedSubview(footer)
    }

    private func makeFooterButton(_ title: String, symbol: String,
                                  action: @escaping () -> Void) -> HoverRow {
        let row = HoverRow(frame: .zero)
        let image = NSImage(systemSymbolName: symbol,
                            accessibilityDescription: title)?.withSymbolConfiguration(
            .init(pointSize: 10, weight: .medium))
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = Theme.color(.secondary)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let text = makeLabel(title, font: .label, color: .secondary)
        row.content.addArrangedSubview(imageView)
        row.content.addArrangedSubview(text)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 26),
            row.widthAnchor.constraint(equalToConstant: 84),
        ])
        row.onClick = action
        return row
    }

    private func makeBackBar(_ title: String) -> NSView {
        let row = HoverRow(frame: .zero)
        row.hoverEnabled = false

        let titleField = makeLabel(title, font: .label, color: .secondary)

        let backChip = HoverRow(frame: .zero)
        let backView = NSImageView(image: NSImage(
            systemSymbolName: "chevron.left", accessibilityDescription: "Back") ?? NSImage())
        backView.contentTintColor = Theme.color(.accent)
        backView.translatesAutoresizingMaskIntoConstraints = false
        backChip.content.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        backChip.content.addArrangedSubview(backView)
        backChip.content.addArrangedSubview(
            makeLabel("Back", font: .label, color: .accent))
        NSLayoutConstraint.activate([
            backChip.heightAnchor.constraint(equalToConstant: 22),
        ])
        backChip.onClick = { [weak self] in self?.onAction?(.back) }

        row.content.addArrangedSubview(titleField)
        row.content.addArrangedSubview(makeSpacer())
        row.content.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        row.content.addArrangedSubview(backChip)
        return row
    }

    // MARK: - Refresh

    private func refreshMode() {
        metricsPage?.isHidden = mode != .metrics
        sessionsPage?.isHidden = mode != .sessions
        limitsPage?.isHidden = mode != .limits

        let isMetrics = mode == .metrics
        for button in footerMetricsButtons {
            button.isHidden = !isMetrics
        }
        footerHintField?.isHidden = isMetrics
        switch mode {
        case .sessions:
            footerHintField?.stringValue = "click a row to focus its app"
        case .limits:
            footerHintField?.stringValue = "tap a limit to cycle its preset"
        case .metrics:
            break
        }
        refreshContent()
    }

    private func refreshContent() {
        refreshMetrics()
        refreshClaude()
        refreshSessions()
        refreshLimits()
    }

    private func refreshMetrics() {
        guard metricRows.count == 5 else { return }
        let cpu = metricRows[0]
        let mem = metricRows[1]
        let gpu = metricRows[2]
        let net = metricRows[3]
        let temp = metricRows[4]

        cpu.update(value: Format.percent(snapshot.cpu.total),
                   detail: alertDetail(.cpu)
                       ?? DetailText("load \(String(format: "%.2f", snapshot.cpu.load1))  ·  \(snapshot.cpu.perCore.count) cores",
                                     Theme.color(.tertiary)),
                   fraction: snapshot.cpu.total / 100)
        mem.update(value: "\(Format.bytes(snapshot.memory.used)) / \(Format.bytes(snapshot.memory.total))",
                   detail: alertDetail(.mem)
                       ?? DetailText("wired \(Format.bytes(snapshot.memory.wired))  ·  comp \(Format.bytes(snapshot.memory.compressed))  ·  swap \(Format.bytes(snapshot.memory.swapUsed))",
                                     Theme.color(.tertiary)),
                   fraction: snapshot.memory.fraction)
        gpu.update(value: snapshot.gpu.available
                       ? Format.percent(snapshot.gpu.utilization) : "--",
                   detail: alertDetail(.gpu) ?? DetailText("", Theme.color(.tertiary)),
                   fraction: snapshot.gpu.available
                       ? snapshot.gpu.utilization / 100 : nil)
        net.update(value: "\u{2193} \(Format.rate(snapshot.network.down))   \u{2191} \(Format.rate(snapshot.network.up))",
                   detail: DetailText(activeInterfaceDetail() ?? "",
                                      Theme.color(.tertiary)),
                   fraction: nil)
        temp.update(value: temperatureValue(),
                    detail: DetailText(temperatureDetail() ?? "",
                                       Theme.color(.tertiary)),
                    fraction: nil)
    }

    private func refreshClaude() {
        guard claudeRows.count == 2,
              let status = claudeStatusField,
              let extra = claudeExtraField else { return }

        if !claude.hasData {
            status.stringValue = "NO USAGE"
            status.textColor = Theme.color(.warning)
        } else if claude.stale {
            status.stringValue = claude.source == .local
                ? "LOCAL ESTIMATE" : "STALE"
            status.textColor = Theme.color(.warning)
        } else {
            status.stringValue = (claude.plan ?? "claude").uppercased()
            status.textColor = Theme.color(.secondary)
        }

        let five = claudeRows[0]
        let weekly = claudeRows[1]

        var fiveDetail: DetailText?
        if let projection = claude.projection {
            fiveDetail = DetailText(projection.text, roleColor(projection.role))
        } else if let reset = claude.fiveHourReset {
            let remaining = reset.timeIntervalSinceNow
            let suffix = remaining > 0
                ? "resets in \(Format.countdown(remaining))" : "reset"
            fiveDetail = DetailText(suffix, Theme.color(.tertiary))
        }
        five.update(value: claude.fiveHour.map { Format.percent($0) } ?? "--",
                    fraction: claude.fiveHour.map { $0 / 100 },
                    detail: fiveDetail)

        let weeklyDetail: DetailText
        if let weeklyText = claude.weeklyText {
            weeklyDetail = DetailText(weeklyText, Theme.color(.tertiary))
        } else if let reset = claude.sevenDayReset {
            let remaining = reset.timeIntervalSinceNow
            let suffix = remaining > 0
                ? "resets in \(Format.countdown(remaining))" : "reset"
            weeklyDetail = DetailText(suffix, Theme.color(.tertiary))
        } else {
            weeklyDetail = DetailText("", Theme.color(.tertiary))
        }
        weekly.update(value: claude.sevenDay.map { Format.percent($0) } ?? "--",
                      fraction: claude.sevenDay.map { $0 / 100 },
                      detail: weeklyDetail)

        var extraParts: [String] = []
        if let tokens = claude.localTokens, tokens > 0 {
            extraParts.append("local usage ~\(Self.tokenString(tokens)) tokens / 5h")
        }
        if let reason = claude.failureReason,
           claude.hasData ? claude.source != .local : true {
            extraParts.append(reason.lowercased())
        }
        extra.stringValue = extraParts.joined(separator: "  ·  ")
        extra.isHidden = extraParts.isEmpty
    }

    private func refreshSessions() {
        guard mode == .sessions,
              let list = sessionListStack,
              let empty = sessionsEmptyField,
              let more = sessionsMoreField else { return }

        for subview in list.arrangedSubviews {
            list.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        empty.stringValue = sessions.isEmpty ? "no sessions running" : ""
        empty.isHidden = !sessions.isEmpty
        more.isHidden = sessions.count <= 12
        if sessions.count > 12 {
            more.stringValue = "+ \(sessions.count - 12) more"
        }

        for session in sessions.prefix(12) {
            let row = HoverRow(frame: .zero)
            let chipColor: Theme.ColorToken = session.kind == .claude
                ? .warning : .success
            let chip = makeLabel(session.kind == .claude ? "CLAUDE" : "OC",
                                 font: .tag, color: chipColor)
            let name = makeLabel(Self.leaf(session), font: .row, color: .primary)
            name.lineBreakMode = .byTruncatingTail
            let tty = makeLabel(session.tty, font: .detail, color: .tertiary)
            row.content.addArrangedSubview(chip)
            row.content.addArrangedSubview(name)
            row.content.addArrangedSubview(makeSpacer())
            row.content.addArrangedSubview(tty)
            row.content.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            row.content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 24),
                row.widthAnchor.constraint(equalToConstant: cardWidth),
            ])
            row.onClick = { [weak self] in self?.onAction?(.focus(pid: session.pid)) }
            list.addArrangedSubview(row)
        }
    }

    private func refreshLimits() {
        guard mode == .limits, let alertStack = limitsAlertsStack else { return }
        for subview in alertStack.arrangedSubviews {
            alertStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        for alert in alerts {
            let line = makeLabel(alert.text, font: .detail,
                                 color: alert.severity == .red ? .danger : .warning)
            alertStack.addArrangedSubview(line)
        }
        alertStack.isHidden = alerts.isEmpty
        for row in limitRows {
            row.update(percent: thresholds.percent(for: row.kind))
        }
    }

    // MARK: - Helpers

    private func alertDetail(_ kind: ThresholdKind) -> DetailText? {
        guard let alert = alerts.first(where: { $0.metric == kind }) else { return nil }
        let color: NSColor = alert.severity == .red
            ? Theme.color(.danger) : Theme.color(.warning)
        return DetailText(alert.text, color)
    }

    private func roleColor(_ role: UsageProjection.Role) -> NSColor {
        switch role {
        case .green: return Theme.color(.success)
        case .yellow: return Theme.color(.warning)
        case .orange: return NSColor.systemOrange
        case .red: return Theme.color(.danger)
        }
    }

    private static func leaf(_ session: RunningSession) -> String {
        session.directory.map { ($0 as NSString).lastPathComponent }
            ?? (session.cwd as NSString).lastPathComponent
    }

    private static func tokenString(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1000 {
            return String(format: "%.0fK", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }

    private func temperatureValue() -> String {
        guard snapshot.temperature.available else { return "--" }
        if let cpu = snapshot.temperature.cpu {
            return Format.temperature(cpu)
        }
        return Format.temperature(snapshot.temperature.peak)
    }

    private func temperatureDetail() -> String? {
        guard snapshot.temperature.available else { return "sensors unavailable" }
        var parts: [String] = []
        if let gpu = snapshot.temperature.gpu {
            parts.append("gpu \(Format.temperature(gpu))")
        }
        if let peak = snapshot.temperature.peak {
            parts.append("peak \(Format.temperature(peak))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func activeInterfaceDetail() -> String? {
        guard let iface = snapshot.network.interfaces.max(by: {
            ($0.down + $0.up) < ($1.down + $1.up)
        }) else { return nil }
        return iface.name
    }
}

struct DetailText {
    let text: String
    let color: NSColor
    init(_ text: String, _ color: NSColor) {
        self.text = text
        self.color = color
    }
}

func tierColor(_ fraction: Double) -> NSColor {
    if fraction >= 0.9 { return Theme.color(.danger) }
    if fraction >= 0.75 { return NSColor.systemOrange }
    if fraction >= 0.55 { return Theme.color(.warning) }
    return Theme.color(.success)
}

private func makeLabel(_ text: String, font token: Theme.FontToken,
                       color token2: Theme.ColorToken,
                       align: NSTextAlignment = .left) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = Theme.font(token)
    field.textColor = Theme.color(token2)
    field.alignment = align
    field.lineBreakMode = .byTruncatingTail
    field.maximumNumberOfLines = 1
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

private func makeSpacer() -> NSView {
    let space = NSView()
    space.setContentHuggingPriority(.defaultLow, for: .horizontal)
    space.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return space
}

final class MetricRowView: NSStackView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let bar: MetricBar?
    private let detailLabel: NSTextField
    private let includesBar: Bool

    init(title: String, includesBar: Bool) {
        self.includesBar = includesBar
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Theme.font(.label)
        titleLabel.textColor = Theme.color(.secondary)

        valueLabel = NSTextField(labelWithString: "--")
        valueLabel.font = Theme.font(.value)
        valueLabel.textColor = Theme.color(.primary)
        valueLabel.alignment = .right

        detailLabel = NSTextField(labelWithString: " ")
        detailLabel.font = Theme.font(.detail)
        detailLabel.textColor = Theme.color(.tertiary)

        bar = includesBar ? MetricBar(frame: .zero) : nil

        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3
        edgeInsets = NSEdgeInsetsZero

        let topLine = NSStackView()
        topLine.orientation = .horizontal
        topLine.spacing = 4
        topLine.edgeInsets = NSEdgeInsetsZero
        topLine.addArrangedSubview(titleLabel)
        topLine.addArrangedSubview(makeSpacerView())
        topLine.addArrangedSubview(valueLabel)
        addArrangedSubview(topLine)

        if let bar = bar {
            addArrangedSubview(bar)
            bar.heightAnchor.constraint(
                equalToConstant: Theme.barHeight).isActive = true
            bar.leadingAnchor.constraint(
                equalTo: leadingAnchor).isActive = true
            bar.trailingAnchor.constraint(
                equalTo: trailingAnchor).isActive = true
        }
        addArrangedSubview(detailLabel)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    func update(value: String, detail: DetailText?, fraction: Double?) {
        valueLabel.stringValue = value
        detailLabel.stringValue = detail?.text ?? " "
        detailLabel.textColor = detail?.color ?? Theme.color(.tertiary)
        guard let bar else { return }
        if let fraction {
            bar.isHidden = false
            bar.fraction = fraction
            bar.fill = tierColor(fraction)
        } else {
            bar.isHidden = true
        }
    }

    private func makeSpacerView() -> NSView {
        let space = NSView()
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return space
    }
}

final class ClaudeWindowRow: NSStackView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let bar = MetricBar(frame: .zero)
    private let detailLabel: NSTextField

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Theme.font(.label)
        titleLabel.textColor = Theme.color(.secondary)

        valueLabel = NSTextField(labelWithString: "--")
        valueLabel.font = Theme.font(.value)
        valueLabel.textColor = Theme.color(.primary)
        valueLabel.alignment = .right

        detailLabel = NSTextField(labelWithString: " ")
        detailLabel.font = Theme.font(.detail)
        detailLabel.textColor = Theme.color(.tertiary)

        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3
        edgeInsets = NSEdgeInsetsZero

        let topLine = NSStackView()
        topLine.orientation = .horizontal
        topLine.spacing = 4
        topLine.edgeInsets = NSEdgeInsetsZero
        topLine.addArrangedSubview(titleLabel)
        topLine.addArrangedSubview(makeSpacerView())
        topLine.addArrangedSubview(valueLabel)
        addArrangedSubview(topLine)
        addArrangedSubview(bar)
        addArrangedSubview(detailLabel)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Theme.barHeight),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    func update(value: String, fraction: Double?, detail: DetailText?) {
        valueLabel.stringValue = value
        let clamped = fraction ?? 0
        bar.isHidden = fraction == nil
        bar.fraction = clamped
        bar.fill = tierColor(clamped)
        detailLabel.stringValue = detail?.text ?? " "
        detailLabel.textColor = detail?.color ?? Theme.color(.tertiary)
        detailLabel.isHidden = detail == nil
    }

    private func makeSpacerView() -> NSView {
        let space = NSView()
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return space
    }
}

final class LimitRowView: NSView {
    public let kind: ThresholdKind
    public var hostAction: PanelViewController?
    public var hoverRow: HoverRow
    private let valueLabel: NSTextField

    init(kind: ThresholdKind, note: String, width: CGFloat) {
        self.kind = kind
        let titleLabel = NSTextField(labelWithString: kind.rawValue.uppercased())
        titleLabel.font = Theme.font(.row)
        titleLabel.textColor = Theme.color(.primary)

        let noteLabel = NSTextField(labelWithString: note)
        noteLabel.font = Theme.font(.detail)
        noteLabel.textColor = Theme.color(.tertiary)

        valueLabel = NSTextField(labelWithString: "≥ --%")
        valueLabel.font = Theme.font(.row)
        valueLabel.textColor = Theme.color(.accent)
        valueLabel.alignment = .right

        let row = HoverRow(frame: .zero)
        hoverRow = row
        row.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)
        row.content.addArrangedSubview(titleLabel)
        row.content.addArrangedSubview(noteLabel)
        row.content.addArrangedSubview(makeSpacerInternal())
        row.content.addArrangedSubview(valueLabel)
        row.onClick = { [weak self] in
            guard let kind = self?.kind else { return }
            self?.hostAction?.onAction?(.cycleLimit(kind))
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 46),
        ])

        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    func update(percent: Int) {
        valueLabel.stringValue = "≥ \(percent)%"
    }
}

private func makeSpacerInternal() -> NSView {
    let space = NSView()
    space.setContentHuggingPriority(.defaultLow, for: .horizontal)
    space.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return space
}

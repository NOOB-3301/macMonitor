import AppKit

public final class PanelView: NSView {
    public static let size = NSSize(width: 344, height: 436)

    private enum Palette {
        static let primary = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.00, alpha: 1)
        static let secondary = NSColor(calibratedRed: 0.74, green: 0.78, blue: 0.85, alpha: 1)
        static let tertiary = NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.70, alpha: 1)
        static let track = NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.32, alpha: 1)
        static let divider = NSColor(calibratedRed: 0.30, green: 0.33, blue: 0.40, alpha: 1)
        static let green = NSColor(calibratedRed: 0.30, green: 0.86, blue: 0.50, alpha: 1)
        static let yellow = NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.30, alpha: 1)
        static let orange = NSColor(calibratedRed: 1.00, green: 0.60, blue: 0.22, alpha: 1)
        static let red = NSColor(calibratedRed: 1.00, green: 0.40, blue: 0.42, alpha: 1)
    }

    private var snapshot = Snapshot()
    private var claude = ClaudeUsage()

    private let padding: CGFloat = 16
    private let labelFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

    public override var isFlipped: Bool { false }

    public func update(snapshot: Snapshot, claude: ClaudeUsage) {
        self.snapshot = snapshot
        self.claude = claude
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        let content = bounds.insetBy(dx: padding, dy: padding)
        var y = content.maxY - 2

        y = drawMetric(
            title: "CPU",
            value: Format.percent(snapshot.cpu.total),
            detail: "load \(String(format: "%.2f", snapshot.cpu.load1))  ·  \(snapshot.cpu.perCore.count) cores",
            fraction: snapshot.cpu.total / 100,
            y: y
        )
        y = drawMetric(
            title: "MEMORY",
            value: "\(Format.bytes(snapshot.memory.used)) / \(Format.bytes(snapshot.memory.total))",
            detail: "wired \(Format.bytes(snapshot.memory.wired))  ·  comp \(Format.bytes(snapshot.memory.compressed))  ·  swap \(Format.bytes(snapshot.memory.swapUsed))",
            fraction: snapshot.memory.fraction,
            y: y
        )
        y = drawMetric(
            title: "GPU",
            value: snapshot.gpu.available ? Format.percent(snapshot.gpu.utilization) : "--",
            detail: nil,
            fraction: snapshot.gpu.available ? snapshot.gpu.utilization / 100 : nil,
            y: y
        )
        y = drawMetric(
            title: "NETWORK",
            value: "\u{2193} \(Format.rate(snapshot.network.down))   \u{2191} \(Format.rate(snapshot.network.up))",
            detail: activeInterfaceDetail(),
            fraction: nil,
            y: y
        )
        y = drawMetric(
            title: "TEMPERATURE",
            value: temperatureValue(),
            detail: temperatureDetail(),
            fraction: nil,
            y: y
        )

        y -= 8
        Palette.divider.setFill()
        NSRect(x: content.minX, y: y, width: content.width, height: 1).fill()
        y -= 14

        drawClaude(from: y)
    }

    private func drawMetric(title: String, value: String, detail: String?,
                            fraction: Double?, y: CGFloat) -> CGFloat {
        let content = bounds.insetBy(dx: padding, dy: padding)
        var cursor = y

        drawText(title, at: NSPoint(x: content.minX, y: cursor - 12),
                 font: labelFont, color: Palette.secondary,
                 alignment: .left, width: content.width)
        drawText(value, at: NSPoint(x: content.minX, y: cursor - 14),
                 font: valueFont, color: Palette.primary,
                 alignment: .right, width: content.width)
        cursor -= 23

        if let fraction {
            drawBar(rect: NSRect(x: content.minX, y: cursor - 5,
                                 width: content.width, height: 5),
                    fraction: fraction, color: barColor(for: fraction))
            cursor -= 12
        }

        if let detail {
            drawText(detail, at: NSPoint(x: content.minX, y: cursor - 11),
                     font: detailFont, color: Palette.tertiary,
                     alignment: .left, width: content.width)
            cursor -= 15
        }

        return cursor - 8
    }

    private func drawClaude(from y: CGFloat) {
        let content = bounds.insetBy(dx: padding, dy: padding)
        var cursor = y

        let plan = (claude.plan ?? "claude").uppercased()
        let status: String
        let statusColor: NSColor
        if claude.stale {
            status = claude.source == .local ? "LOCAL ESTIMATE" : "STALE"
            statusColor = Palette.orange
        } else {
            status = plan
            statusColor = Palette.secondary
        }

        drawText("CLAUDE", at: NSPoint(x: content.minX, y: cursor - 12),
                 font: labelFont, color: Palette.secondary,
                 alignment: .left, width: content.width)
        drawText(status, at: NSPoint(x: content.minX, y: cursor - 12),
                 font: labelFont, color: statusColor,
                 alignment: .right, width: content.width)
        cursor -= 23

        cursor = drawClaudeWindow(
            title: "5 hour",
            utilization: claude.fiveHour,
            reset: claude.fiveHourReset,
            y: cursor,
            width: content.width,
            x: content.minX
        )
        cursor = drawClaudeWindow(
            title: "weekly",
            utilization: claude.sevenDay,
            reset: claude.sevenDayReset,
            y: cursor,
            width: content.width,
            x: content.minX
        )

        if let tokens = claude.localTokens, tokens > 0 {
            drawText("local usage ~\(tokenString(tokens)) tokens / 5h",
                     at: NSPoint(x: content.minX, y: cursor - 11),
                     font: detailFont, color: Palette.tertiary,
                     alignment: .left, width: content.width)
            cursor -= 14
        }

        if claude.failureReason != nil, claude.source != .local {
            drawText(claude.failureReason!.lowercased(),
                     at: NSPoint(x: content.minX, y: cursor - 11),
                     font: detailFont, color: Palette.tertiary,
                     alignment: .left, width: content.width)
        }
    }

    private func drawClaudeWindow(title: String, utilization: Double?, reset: Date?,
                                  y: CGFloat, width: CGFloat, x: CGFloat) -> CGFloat {
        var cursor = y
        let value = utilization.map { Format.percent($0) } ?? "--"
        drawText(title, at: NSPoint(x: x, y: cursor - 11),
                 font: detailFont, color: Palette.secondary,
                 alignment: .left, width: width)
        drawText(value, at: NSPoint(x: x, y: cursor - 12),
                 font: valueFont, color: Palette.primary,
                 alignment: .right, width: width)
        cursor -= 16

        if let utilization {
            drawBar(rect: NSRect(x: x, y: cursor - 5, width: width, height: 5),
                    fraction: utilization / 100,
                    color: barColor(for: utilization / 100))
        }
        cursor -= 11

        if let reset {
            let remaining = reset.timeIntervalSinceNow
            let suffix = remaining > 0 ? "resets in \(Format.countdown(remaining))" : "reset"
            drawText(suffix, at: NSPoint(x: x, y: cursor - 10),
                     font: detailFont, color: Palette.tertiary,
                     alignment: .left, width: width)
            cursor -= 13
        }
        return cursor - 5
    }

    private func drawText(_ string: String, at point: NSPoint, font: NSFont,
                          color: NSColor, alignment: NSTextAlignment,
                          width: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let rect = NSRect(x: point.x, y: point.y, width: width,
                          height: font.pointSize + 4)
        (string as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawBar(rect: NSRect, fraction: Double, color: NSColor) {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        Palette.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2,
                     yRadius: rect.height / 2).fill()
        guard clamped > 0 else { return }
        let fill = NSRect(x: rect.minX, y: rect.minY,
                          width: max(rect.height, rect.width * clamped),
                          height: rect.height)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: rect.height / 2,
                     yRadius: rect.height / 2).fill()
    }

    private func barColor(for fraction: Double) -> NSColor {
        if fraction >= 0.9 { return Palette.red }
        if fraction >= 0.75 { return Palette.orange }
        if fraction >= 0.55 { return Palette.yellow }
        return Palette.green
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

    private func tokenString(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1000 {
            return String(format: "%.0fK", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }
}

import AppKit

/// Centralized design tokens for the menu-bar panel UI.
public enum Theme {
    public enum ColorToken: CaseIterable {
        case primary
        case secondary
        case tertiary
        case quaternary
        case accent
        case success
        case warning
        case danger
        /// Track fill behind progress bars.
        case fill
        /// Hover highlight for interactive rows.
        case fillHover
        /// Inner card surface drawn on top of vibrancy.
        case elevated
        case separator
    }

    public enum FontToken: CaseIterable {
        /// Large metric value; monospaced digits.
        case value
        case label
        case detail
        /// Tiny bold section tag.
        case tag
        /// Session row text; monospaced digits.
        case row
    }

    public enum Radius: CaseIterable {
        case panel
        case card
        /// Corner radius for the 7pt-tall metric bars.
        case bar
        case chip
        case pill
    }

    public static func color(_ token: ColorToken) -> NSColor {
        if let cached = colorCache[token] { return cached }
        let resolved: NSColor
        switch token {
        case .primary:
            resolved = .labelColor
        case .secondary:
            resolved = .secondaryLabelColor
        case .tertiary:
            resolved = .tertiaryLabelColor
        case .quaternary:
            resolved = .quaternaryLabelColor
        case .accent:
            resolved = .systemBlue
        case .success:
            resolved = .systemGreen
        case .warning:
            resolved = .systemYellow
        case .danger:
            resolved = .systemRed
        case .separator:
            resolved = .separatorColor
        case .fill:
            resolved = dynamicColor(
                light: NSColor.black.withAlphaComponent(0.08),
                dark: NSColor.white.withAlphaComponent(0.12)
            )
        case .fillHover:
            resolved = dynamicColor(
                light: NSColor.black.withAlphaComponent(0.06),
                dark: NSColor.white.withAlphaComponent(0.09)
            )
        case .elevated:
            resolved = dynamicColor(
                light: NSColor.white.withAlphaComponent(0.60),
                dark: NSColor.white.withAlphaComponent(0.06)
            )
        }
        colorCache[token] = resolved
        return resolved
    }

    public static func font(_ token: FontToken) -> NSFont {
        if let cached = fontCache[token] { return cached }
        let resolved: NSFont
        switch token {
        case .value:
            resolved = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        case .label:
            resolved = .systemFont(ofSize: 12, weight: .medium)
        case .detail:
            resolved = .systemFont(ofSize: 10.5, weight: .regular)
        case .tag:
            resolved = .systemFont(ofSize: 9, weight: .bold)
        case .row:
            resolved = .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        }
        fontCache[token] = resolved
        return resolved
    }

    public static func radius(_ token: Radius) -> CGFloat {
        switch token {
        case .panel: return 20
        case .card: return 11
        case .bar: return 3.5
        case .chip: return 7
        case .pill: return 999
        }
    }

    public static let spacingLine: CGFloat = 4
    public static let spacingStack: CGFloat = 8
    public static let spacingGroup: CGFloat = 14
    public static let paddingPanel: CGFloat = 18
    public static let paddingCard: CGFloat = 12
    public static let barHeight: CGFloat = 7
    public static let panelSize = NSSize(width: 360, height: 470)

    private static var colorCache: [ColorToken: NSColor] = [:]
    private static var fontCache: [FontToken: NSFont] = [:]

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: "Theme.dynamic") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }
}

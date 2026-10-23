import AppKit

func withDisabledActions(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

public final class GlassCard: NSView {
    public static var forceFallbackSurface = false

    public let content = NSView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        content.translatesAutoresizingMaskIntoConstraints = false
        applySurface()
    }

    public required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if !usesGlass {
            layer?.backgroundColor = Theme.color(.elevated).cgColor
        }
    }

    private var usesGlass = false

    private func applySurface() {
        if #available(macOS 26.0, *), !GlassCard.forceFallbackSurface {
            usesGlass = true
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.radius(.card)
            glass.tintColor = Theme.color(.elevated)
            glass.contentView = content
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        } else {
            wantsLayer = true
            layer?.backgroundColor = Theme.color(.elevated).cgColor
            layer?.cornerRadius = Theme.radius(.card)
            layer?.masksToBounds = true
            addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }
}

public final class HoverRow: NSView {
    public var onClick: (() -> Void)?
    public var hoverEnabled = true

    public let content = NSStackView()
    private let highlight = CALayer()
    private var hovered = false {
        didSet {
            withDisabledActions {
                highlight.opacity = hovered ? 1 : 0
            }
        }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        highlight.backgroundColor = Theme.color(.fillHover).cgColor
        highlight.cornerRadius = Theme.radius(.chip)
        highlight.opacity = 0
        layer?.addSublayer(highlight)

        content.orientation = .horizontal
        content.alignment = .centerY
        content.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    public required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    public override func layout() {
        super.layout()
        refreshHighlightFrame()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        highlight.backgroundColor = Theme.color(.fillHover).cgColor
    }

    private func refreshHighlightFrame() {
        withDisabledActions {
            var frame = bounds
            frame.origin = .zero
            highlight.frame = frame
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            if area.owner === self {
                removeTrackingArea(area)
            }
        }
        guard bounds.width > 0, bounds.height > 0 else { return }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) {
        guard hoverEnabled else { return }
        hovered = true
    }

    public override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    public override func mouseDown(with event: NSEvent) {
        guard hoverEnabled else { return }
        onClick?()
    }

    public override func resetCursorRects() {
        guard hoverEnabled else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    public override var isFlipped: Bool { true }
}

public final class MetricBar: NSView {
    public var fraction: Double = 0 {
        didSet { applyFraction(animated: true) }
    }
    public var fill: NSColor = Theme.color(.success) {
        didSet { fillLayer.backgroundColor = fill.cgColor }
    }

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let radius = Theme.radius(.bar)
        trackLayer.backgroundColor = Theme.color(.fill).cgColor
        trackLayer.cornerRadius = radius
        fillLayer.backgroundColor = fill.cgColor
        fillLayer.cornerRadius = radius
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    public required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    public override func layout() {
        super.layout()
        applyFraction(animated: false)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        trackLayer.backgroundColor = Theme.color(.fill).cgColor
        fillLayer.backgroundColor = fill.cgColor
    }

    private func applyFraction(animated: Bool) {
        var frame = bounds
        frame.origin = .zero
        let clamped = CGFloat(min(max(fraction, 0), 1))
        var fillFrame = frame
        fillFrame.size.width = max(bounds.height, bounds.width * clamped)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut))
        }
        trackLayer.frame = frame
        fillLayer.frame = fillFrame
        CATransaction.commit()
    }
}

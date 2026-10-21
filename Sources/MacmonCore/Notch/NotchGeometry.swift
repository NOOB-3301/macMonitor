import AppKit

public struct NotchGeometry: Sendable {
    public let screenFrame: NSRect
    public let notchRect: NSRect
    public let triggerRect: NSRect

    public init(screenFrame: NSRect, notchRect: NSRect, triggerRect: NSRect) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.triggerRect = triggerRect
    }

    public static func make(for screen: NSScreen) -> NotchGeometry? {
        let inset = screen.safeAreaInsets.top
        guard inset > 0 else { return nil }
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }

        let frame = screen.frame
        let width = frame.width - left.width - right.width
        guard width > 40 else { return nil }

        let notch = NSRect(
            x: frame.minX + left.width,
            y: frame.maxY - inset,
            width: width,
            height: inset
        )
        let trigger = NSRect(
            x: notch.minX - 4,
            y: notch.minY - 4,
            width: notch.width + 8,
            height: notch.height + 4
        )
        return NotchGeometry(screenFrame: frame, notchRect: notch,
                             triggerRect: trigger)
    }

    public func panelOrigin(size: NSSize, margin: CGFloat = 8) -> NSPoint {
        var x = notchRect.midX - size.width / 2
        x = min(max(x, screenFrame.minX + margin),
                screenFrame.maxX - size.width - margin)
        let top = notchRect.minY - margin
        return NSPoint(x: x, y: top - size.height)
    }
}

public extension NSScreen {
    static var builtIn: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 } ?? main
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil
    }
}

import AppKit

/// Rounded screen corners: four small black windows per screen, each with a continuous (squircle) corner cut
/// out of it. Small windows instead of one full-screen mask keep the compositing cost negligible. Approach
/// after nisesimadao/Rounder (MIT).
@MainActor
public final class CornerMask {
    private var windows: [ClickThroughWindow] = []
    /// How many corner windows are up (four per screen when on).
    public var windowCount: Int { windows.count }
    private var radius: CGFloat = 0

    public init() {}

    public func show(radius: Double) {
        self.radius = radius
        rebuild()
    }

    public func hide() {
        for window in windows { window.close() }
        windows.removeAll()
    }

    /// Call when screens change.
    public func rebuild() {
        hide()
        guard radius > 0 else { return }
        // A continuous corner bends over about 1.53× its radius.
        let size = ceil(radius * 1.6)
        for screen in NSScreen.screens {
            let f = screen.frame
            let corners: [(NSPoint, Corner)] = [
                (NSPoint(x: f.minX, y: f.maxY - size), .topLeft),
                (NSPoint(x: f.maxX - size, y: f.maxY - size), .topRight),
                (NSPoint(x: f.minX, y: f.minY), .bottomLeft),
                (NSPoint(x: f.maxX - size, y: f.minY), .bottomRight),
            ]
            for (origin, corner) in corners {
                let window = ClickThroughWindow(
                    frame: NSRect(origin: origin, size: NSSize(width: size, height: size)), level: .screenSaver)
                window.sharingType = .none
                window.contentView = CornerView(corner: corner, radius: radius)
                window.orderFrontRegardless()
                windows.append(window)
            }
        }
    }

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private final class CornerView: NSView {
        let corner: Corner
        let radius: CGFloat

        init(corner: Corner, radius: CGFloat) {
            self.corner = corner
            self.radius = radius
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override var isOpaque: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            // A rounded rectangle twice the window's size, placed so only its one corner falls inside.
            let b = bounds
            var screen = CGRect(x: 0, y: 0, width: b.width * 2, height: b.height * 2)
            switch corner {
            case .topLeft: screen.origin = CGPoint(x: 0, y: -b.height)
            case .topRight: screen.origin = CGPoint(x: -b.width, y: -b.height)
            case .bottomLeft: screen.origin = .zero
            case .bottomRight: screen.origin = CGPoint(x: -b.width, y: 0)
            }
            let path = CGMutablePath()
            path.addRect(b)
            path.addPath(Self.continuousRoundedRect(screen, radius: radius))
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
        }

        /// A rounded rectangle with continuous corners like Apple's hardware, built from the same cubic
        /// approximation SwiftUI's `.continuous` style uses.
        static func continuousRoundedRect(_ rect: CGRect, radius r: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let k: CGFloat = 1.528665  // how far the curve starts from the corner, in radii
            let minX = rect.minX
            let maxX = rect.maxX
            let minY = rect.minY
            let maxY = rect.maxY
            let e = r * k
            path.move(to: CGPoint(x: minX + e, y: minY))
            path.addLine(to: CGPoint(x: maxX - e, y: minY))
            path.addCurve(
                to: CGPoint(x: maxX, y: minY + e), control1: CGPoint(x: maxX - r * 0.43, y: minY),
                control2: CGPoint(x: maxX, y: minY + r * 0.43))
            path.addLine(to: CGPoint(x: maxX, y: maxY - e))
            path.addCurve(
                to: CGPoint(x: maxX - e, y: maxY), control1: CGPoint(x: maxX, y: maxY - r * 0.43),
                control2: CGPoint(x: maxX - r * 0.43, y: maxY))
            path.addLine(to: CGPoint(x: minX + e, y: maxY))
            path.addCurve(
                to: CGPoint(x: minX, y: maxY - e), control1: CGPoint(x: minX + r * 0.43, y: maxY),
                control2: CGPoint(x: minX, y: maxY - r * 0.43))
            path.addLine(to: CGPoint(x: minX, y: minY + e))
            path.addCurve(
                to: CGPoint(x: minX + e, y: minY), control1: CGPoint(x: minX, y: minY + r * 0.43),
                control2: CGPoint(x: minX + r * 0.43, y: minY))
            path.closeSubpath()
            return path
        }
    }
}

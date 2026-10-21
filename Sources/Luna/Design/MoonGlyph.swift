import AppKit

/// Luna's menu bar mark: a crescent moon that fills out as brightness rises, from a sliver to nearly full.
enum MoonGlyph {
    /// A template image for the menu bar (macOS tints it). `brightness` 0…1 sets how full the moon is.
    /// `badge` adds a dot at the top right (an update is waiting).
    static func menuBarImage(brightness: Double, badge: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect.insetBy(dx: 2, dy: 2), brightness: brightness)
            if badge {
                // Clear a ring around the dot so it reads against the moon.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 7, height: 7)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 12.5, width: 4.5, height: 4.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Luna"
        return image
    }

    /// The disc minus a second disc offset toward the top left: the further the offset, the fuller the moon.
    static func draw(in rect: NSRect, brightness: Double) {
        let r = min(rect.width, rect.height) / 2
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let shift = r * CGFloat(0.62 + 0.9 * min(max(brightness, 0), 1))
        let moon = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        let shadow = NSBezierPath(
            ovalIn: NSRect(x: center.x - r - shift, y: center.y - r + shift * 0.35, width: 2 * r, height: 2 * r))
        NSGraphicsContext.saveGraphicsState()
        // Clip to everything except the shadow disc, then fill the moon.
        let clip = NSBezierPath(rect: rect.insetBy(dx: -r, dy: -r))
        clip.append(shadow)
        clip.windingRule = .evenOdd
        clip.addClip()
        NSColor.black.setFill()
        moon.fill()
        NSGraphicsContext.restoreGraphicsState()
        // A faint outline of the whole disc keeps a thin crescent legible.
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let outline = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        outline.lineWidth = 1
        outline.stroke()
    }
}

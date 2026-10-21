import AppKit
import CoreGraphics

/// Software dimming and the XDR lift, one owner for all displays: either the display's gamma table scaled
/// (down to dim, above 1 into the HDR headroom for XDR), or a black shade window over it. Gamma looks better (it also dims the pointer and stays out of screenshots); the
/// shade works on displays without a gamma table (Sidecar, AirPlay, DisplayLink) and alongside apps like
/// f.lux that also set gamma.
@MainActor
public final class Dimmer {
    public static let shared = Dimmer()

    public enum Method: Equatable {
        case gamma, overlay
    }

    private struct Table {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    private var originals: [CGDirectDisplayID: Table] = [:]
    private var gammaFactors: [CGDirectDisplayID: Double] = [:]
    private var shades: [CGDirectDisplayID: ClickThroughWindow] = [:]
    private var nudgers: [CGDirectDisplayID: ClickThroughWindow] = [:]

    private init() {}

    /// Lets `factor` of the display's light through (1 = untouched, above 1 = XDR, colour table only).
    public func set(_ factor: Double, for display: CGDirectDisplayID, method: Method) {
        let factor = factor.clamped(to: 0.02...4)
        switch method {
        case .gamma:
            removeShade(display)
            setGamma(factor, display)
        case .overlay:
            if gammaFactors[display] != nil { restoreGamma(display) }
            setShade(1 - min(factor, 1), display)
        }
    }

    /// Whether the display has a colour table Luna can use (not AirPlay, Sidecar or DisplayLink).
    public func hasColourTable(_ display: CGDirectDisplayID) -> Bool {
        original(display) != nil
    }

    /// Puts Luna's table back if something (macOS, another app) replaced it.
    public func restoreIfReset(_ display: CGDirectDisplayID) {
        guard let factor = gammaFactors[display], let original = original(display),
            let expected = original.red.max().map({ Double($0) * factor })
        else { return }
        var red = [CGGammaValue](repeating: 0, count: 256)
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, 256, &red, &green, &blue, &count) == .success else { return }
        let current = Double(red.prefix(Int(count)).max() ?? 0)
        if abs(current - expected) > 0.01 { applyGamma(factor, display) }
    }

    public func reset(_ display: CGDirectDisplayID) {
        removeShade(display)
        if gammaFactors[display] != nil { restoreGamma(display) }
    }

    /// Back to the system's colour profiles everywhere, e.g. when quitting.
    public func resetAll() {
        for display in Array(shades.keys) { removeShade(display) }
        if !gammaFactors.isEmpty {
            gammaFactors.removeAll()
            CGDisplayRestoreColorSyncSettings()
        }
        for window in nudgers.values { window.close() }
        nudgers.removeAll()
    }

    /// After sleep or a display change macOS restores the profiles; put Luna's dimming back.
    public func reapply() {
        // Start from the system's own tables: if Luna's were still applied, capturing them as the originals
        // would dim or boost twice.
        if !gammaFactors.isEmpty { CGDisplayRestoreColorSyncSettings() }
        originals.removeAll()
        for (display, factor) in gammaFactors { applyGamma(factor, display) }
        for (display, shade) in shades {
            if let screen = NSScreen.with(displayID: display) { shade.setFrame(screen.frame, display: false) }
        }
    }

    // MARK: Gamma

    private func setGamma(_ factor: Double, _ display: CGDirectDisplayID) {
        if abs(factor - 1) < 0.001 {
            if gammaFactors[display] != nil { restoreGamma(display) }
            return
        }
        gammaFactors[display] = factor
        applyGamma(factor, display)
    }

    private func applyGamma(_ factor: Double, _ display: CGDirectDisplayID) {
        guard let original = original(display) else { return }
        let scale = CGGammaValue(factor)
        let red = original.red.map { $0 * scale }
        let green = original.green.map { $0 * scale }
        let blue = original.blue.map { $0 * scale }
        CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
        nudge(display)
    }

    private func restoreGamma(_ display: CGDirectDisplayID) {
        gammaFactors[display] = nil
        // Restores every display, so put the others' dimming back.
        CGDisplayRestoreColorSyncSettings()
        for (other, factor) in gammaFactors { applyGamma(factor, other) }
        nudge(display)
    }

    private func original(_ display: CGDirectDisplayID) -> Table? {
        if let table = originals[display] { return table }
        let capacity: UInt32 = 256
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0
        else { return nil }
        let table = Table(
            red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))),
            blue: Array(blue.prefix(Int(count))))
        originals[display] = table
        return table
    }

    /// WindowServer only applies a new gamma table when something on screen redraws. Flicker a 1-pixel,
    /// nearly invisible window so the change shows at once.
    private func nudge(_ display: CGDirectDisplayID) {
        guard let screen = NSScreen.with(displayID: display) else { return }
        let window =
            nudgers[display]
            ?? {
                let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
                let window = ClickThroughWindow(frame: frame, level: .screenSaver)
                window.sharingType = .none
                window.backgroundColor = .black
                window.alphaValue = 0.01
                window.orderFrontRegardless()
                nudgers[display] = window
                return window
            }()
        window.alphaValue = window.alphaValue < 0.015 ? 0.02 : 0.01
    }

    // MARK: Shade

    private func setShade(_ opacity: Double, _ display: CGDirectDisplayID) {
        guard opacity > 0.001 else {
            removeShade(display)
            return
        }
        guard let screen = NSScreen.with(displayID: display) else { return }
        let shade =
            shades[display]
            ?? {
                let window = ClickThroughWindow(
                    frame: screen.frame, level: NSWindow.Level(Int(CGShieldingWindowLevel())))
                window.backgroundColor = .black
                // Keep the shade out of screenshots and recordings.
                window.sharingType = .none
                window.alphaValue = 0
                window.orderFrontRegardless()
                shades[display] = window
                return window
            }()
        shade.setFrame(screen.frame, display: false)
        shade.alphaValue = opacity
    }

    private func removeShade(_ display: CGDirectDisplayID) {
        shades.removeValue(forKey: display)?.close()
    }
}

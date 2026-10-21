import AppKit
import CoreGraphics

/// Software dimming, one owner for all displays: either the display's gamma table scaled down, or a black
/// shade window over it. Gamma looks better (it also dims the pointer and stays out of screenshots); the
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

    /// Lets `factor` of the display's light through (1 = untouched).
    public func set(_ factor: Double, for display: CGDirectDisplayID, method: Method) {
        let factor = factor.clamped(to: 0.02...1)
        switch method {
        case .gamma:
            removeShade(display)
            setGamma(factor, display)
        case .overlay:
            if gammaFactors[display] != nil { restoreGamma(display) }
            setShade(1 - factor, display)
        }
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
        originals.removeAll()
        for (display, factor) in gammaFactors { applyGamma(factor, display) }
        for (display, shade) in shades {
            if let screen = NSScreen.with(displayID: display) { shade.setFrame(screen.frame, display: false) }
        }
    }

    // MARK: Gamma

    private func setGamma(_ factor: Double, _ display: CGDirectDisplayID) {
        if factor >= 0.999 {
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

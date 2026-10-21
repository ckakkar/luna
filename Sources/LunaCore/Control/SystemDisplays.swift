import AppKit
import CPrivate
import CoreGraphics

/// Brightness of the built-in display and Apple's own monitors (Studio Display, Pro Display XDR,
/// LG UltraFine), through the same private framework the brightness keys use.
public enum AppleNative {
    public static func canControl(_ display: CGDirectDisplayID) -> Bool {
        LunaDSCanChangeBrightness(display)
    }

    public static func brightness(_ display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        return LunaDSGetBrightness(display, &value) == 0 ? Double(value) : nil
    }

    public static func setBrightness(_ value: Double, for display: CGDirectDisplayID) {
        _ = LunaDSSetBrightness(display, Float(value.clamped(to: 0...1)))
    }
}

/// Observes a built-in or Apple display's brightness however it changes (keys, Control Center, ambient
/// light), for "Match Mac".
@MainActor
public final class BrightnessObserver {
    public let display: CGDirectDisplayID
    private let onChange: @MainActor (Double) -> Void
    private var registered = false

    public init(display: CGDirectDisplayID, onChange: @escaping @MainActor (Double) -> Void) {
        self.display = display
        self.onChange = onChange
        Self.observers[display] = self
        registered =
            LunaDSRegisterForBrightnessChanges(display, Self.token(display)) { _, observer, _, _, userInfo in
                guard let observer, let info = (userInfo as NSDictionary?) as? [String: Any],
                    let value = (info["value"] as? NSNumber)?.doubleValue
                else { return }
                let display = CGDirectDisplayID(UInt(bitPattern: observer) - 1)
                Task { @MainActor in BrightnessObserver.observers[display]?.onChange(value) }
            } == 0
    }

    public func stop() {
        if registered { LunaDSUnregisterForBrightnessChanges(display, Self.token(display)) }
        registered = false
        if Self.observers[display] === self { Self.observers[display] = nil }
    }

    private static var observers: [CGDirectDisplayID: BrightnessObserver] = [:]

    // The callback can't capture context, so the display ID travels as the observer pointer.
    private static func token(_ display: CGDirectDisplayID) -> UnsafeRawPointer {
        UnsafeRawPointer(bitPattern: UInt(display) + 1)!
    }
}

/// Turning a display off without unplugging it: macOS detaches it as if disconnected, and the other displays
/// take over. Turned back on the same way; a restart or replugging also brings it back.
public enum DisplayPower {
    public static var isAvailable: Bool { LunaCanConfigureDisplayEnabled() }

    @discardableResult
    public static func setEnabled(_ enabled: Bool, display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard LunaConfigureDisplayEnabled(config, display, enabled) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}

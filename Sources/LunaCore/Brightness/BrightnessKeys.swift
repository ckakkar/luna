/// What a press of a brightness key or shortcut does to the displays it targets.
@MainActor
public enum BrightnessKeys {
    /// Steps each target one press up or down and returns the displays changed (for the indicator).
    ///
    /// A media key is left to macOS (nothing changed, empty result) only when macOS handles every target
    /// itself: built-in or Apple displays in their normal range. Otherwise Luna steps them all, Apple displays
    /// included, because once Luna takes the key macOS never sees it. A shortcut is never a system brightness
    /// event, so Luna always steps every target.
    public static func press(
        up: Bool, fine: Bool, fromMediaKey: Bool, targets: [Display], settings: AppSettings
    ) -> [Display] {
        guard !targets.isEmpty else { return [] }
        if fromMediaKey, targets.allSatisfy({ macOSHandles($0, up: up, settings: settings) }) { return [] }
        for display in targets { step(display, up: up, fine: fine, settings: settings) }
        return targets
    }

    /// macOS changes its own displays in the normal range with the brightness keys, with its own indicator.
    /// Past either end (into dimming below 0% or XDR) only Luna can go.
    public static func macOSHandles(_ display: Display, up: Bool, settings: AppSettings) -> Bool {
        guard display.control == .apple, display.level.dim == 0, display.level.boost == 0 else { return false }
        if up, display.level.brightness >= 0.999, allowsBoost(display, settings) { return false }
        if !up, display.level.brightness <= 0.001, settings.allowDimming { return false }
        return true
    }

    static func step(_ display: Display, up: Bool, fine: Bool, settings: AppSettings) {
        let next = SliderZones.step(
            display.level, by: (up ? 1 : -1) * (fine ? 0.25 : 1), allowDimming: settings.allowDimming,
            allowBoost: allowsBoost(display, settings))
        if next.boost > 0, !display.xdr { display.setXDR(true) }
        display.setLevel(next)
    }

    private static func allowsBoost(_ display: Display, _ settings: AppSettings) -> Bool {
        settings.keysEnterXDR && display.isXDRCapable
    }
}

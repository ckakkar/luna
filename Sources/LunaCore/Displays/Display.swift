import AppKit
import CoreGraphics
import Observation

public enum DisplayKind: String, Sendable {
    case builtin
    /// Apple's own monitors, controlled like the built-in display.
    case apple
    /// Monitors reached over DDC/CI (or dimmed in software when they don't answer).
    case external
    /// Sidecar, AirPlay, DisplayLink and other displays without a cable to the GPU.
    case virtual
}

/// How Luna changes a display's brightness.
public enum Control: Sendable, Equatable {
    case apple, ddc, software, preview

    public var label: String {
        switch self {
        case .apple: "Controlled by macOS"
        case .ddc: "Hardware (DDC)"
        case .software: "Software dimming"
        case .preview: "Preview"
        }
    }
}

/// One connected display and everything Luna can do with it.
@MainActor @Observable
public final class Display: Identifiable {
    public let id: CGDirectDisplayID
    /// Stable across reconnects and restarts; settings are saved under it.
    public let uuid: String
    public let systemName: String
    public let kind: DisplayKind
    public let identity: DisplayIdentity

    public internal(set) var control: Control
    public internal(set) var hasContrast = false
    public internal(set) var hasVolume = false
    public internal(set) var hasMute = false
    public internal(set) var hasInput = false
    /// How far past SDR white the screen can go (1 = not at all).
    public internal(set) var edrHeadroom: Double = 1
    public internal(set) var probing = false
    /// The monitor answered a DDC brightness read.
    public internal(set) var hardwareConfirmed = false
    /// The monitor answers DDC at all, even if only with null messages.
    public internal(set) var ddcResponsive = false

    public internal(set) var level: Level
    /// The monitor's contrast, 0–1 of its range.
    public internal(set) var contrast: Double
    public internal(set) var volume: Double
    public internal(set) var muted = false
    public internal(set) var input: UInt16?
    public internal(set) var xdr: Bool

    public var settings: DisplaySettings {
        didSet { store[uuid] = settings }
    }

    @ObservationIgnored let app: AppSettings
    @ObservationIgnored let store: DisplayStore
    @ObservationIgnored var ddc: DDCChannel? {
        didSet { ddc?.timing = settings.slowDDC ? .slow : .normal }
    }
    @ObservationIgnored private var ddcMaximum: [UInt8: UInt16] = [:]
    /// XDR without a colour table: the multiply overlay (fallback).
    @ObservationIgnored private var edr: EDROverlay?
    /// Keeps the display's HDR headroom open while the colour table is lifted, where it isn't open anyway.
    @ObservationIgnored private var edrTrigger: EDRTrigger?
    /// How far XDR lifts the colour table (1 = not at all).
    @ObservationIgnored private var gammaBoost = 1.0
    @ObservationIgnored private var boostWatch: Timer?
    /// XDR is lifting the display's brightness right now.
    public var isBoosting: Bool { edr != nil || gammaBoost > 1.001 }
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var touchedDuringProbe = false
    /// Brightness notifications caused by Luna's own writes are ignored until then.
    @ObservationIgnored private var ownWriteUntil = Date.distantPast
    /// Called after the user changes brightness, so auto brightness can learn from it.
    @ObservationIgnored var onUserBrightness: ((Display) -> Void)?
    /// Asks the controller to look for a DDC channel (when Settings switches to Hardware without one).
    @ObservationIgnored var requestDDC: ((Display) -> Void)?

    init(
        id: CGDirectDisplayID, uuid: String, name: String, kind: DisplayKind, identity: DisplayIdentity,
        control: Control, app: AppSettings, store: DisplayStore
    ) {
        self.id = id
        self.uuid = uuid
        self.systemName = name
        self.kind = kind
        self.identity = identity
        self.control = control
        self.app = app
        self.store = store
        let settings = store[uuid]
        self.settings = settings
        level = settings.level ?? Level(brightness: 0.7)
        contrast = settings.baseContrast ?? 0.7
        volume = settings.volume ?? 0.5
        xdr = settings.xdr
    }

    // MARK: What the panel shows

    public var name: String {
        if let nickname = settings.nickname?.trimmingCharacters(in: .whitespaces), !nickname.isEmpty {
            return nickname
        }
        return systemName
    }

    /// Apple's XDR panels (MacBook Pro, Pro Display XDR) keep their extra brightness in the backlight, so XDR
    /// makes everything brighter.
    public var hasXDRPanel: Bool {
        edrHeadroom > 1.05 && (kind == .builtin || identity.vendor == Self.appleVendor)
    }

    /// HDR monitors report headroom too, but in HDR mode macOS already runs normal content near the panel's
    /// peak (about 1.2× left at full brightness), so it makes room for XDR by dimming everything else. The boost
    /// then nets out dimmer, and wherever it can't reach (Space swipes, video) the screen visibly dips. Off
    /// unless asked for.
    public var offersXDROnHDRMonitor: Bool { edrHeadroom > 1.05 && !hasXDRPanel }

    public var isXDRCapable: Bool { hasXDRPanel || (offersXDROnHDRMonitor && settings.allowXDR) }

    static let appleVendor = 0x0610
    public var hasHardwareBrightness: Bool { control == .apple || control == .ddc || control == .preview }

    /// The monitor answers DDC but keeps its values to itself, so Luna can't tell which controls it has.
    public var reportsNothing: Bool { ddcResponsive && !hasContrast && !hasVolume && input == nil }
    private var tryAll: Bool { ddcResponsive && settings.showAllControls }
    public var offersContrast: Bool { hasContrast || tryAll }
    public var offersVolume: Bool { hasVolume || tryAll }
    public var offersInput: Bool { hasInput || tryAll }
    public var showsVolume: Bool { offersVolume && settings.showVolume }

    public var zones: SliderZones {
        SliderZones(dimming: app.allowDimming, xdr: xdr && isXDRCapable)
    }

    /// Brightness as words for the panel and the indicator: "72%", "−40%" below zero, "221%" in XDR.
    public var brightnessLabel: String {
        if level.dim > 0 { return "−\(Int((level.dim * 100).rounded()))%" }
        if level.boost > 0 { return "\(Int((xdrMultiplier * 100).rounded()))%" }
        return "\(Int((level.brightness * 100).rounded()))%"
    }

    /// The symbol for the current brightness: a moon below zero, a small or full sun above.
    public var brightnessSymbol: String {
        level.dim > 0 ? "moon.fill" : level.boost > 0 || level.brightness >= 0.5 ? "sun.max.fill" : "sun.min.fill"
    }

    /// How much XDR multiplies the light: 1 at 100%, up to the panel's headroom (at most 3.2).
    public var xdrMultiplier: Double { 1 + level.boost * (min(edrHeadroom, 3.2) - 1) }

    /// The brightness slider's position, 0…1 along its track.
    public var position: Double { zones.position(of: level) }

    // MARK: Changing it

    public func setPosition(_ position: Double) {
        setLevel(zones.level(at: position))
    }

    /// Sets brightness. Changes made by the user (not auto brightness) are learned from.
    public func setLevel(_ newLevel: Level, byUser: Bool = true) {
        transition?.cancel()
        transition = nil
        update(newLevel)
        if byUser {
            if probing { touchedDuringProbe = true }
            onUserBrightness?(self)
        }
    }

    /// Glides to a level, for auto brightness and presets.
    public func animate(to target: Level, duration: Double = 1.2) {
        transition?.cancel()
        let start = level
        guard abs(start.signed - target.signed) > 0.004 else { return }
        let steps = max(1, Int(duration * 30))
        transition = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self else { return }
                let t = Double(step) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                self.update(Level(signed: start.signed + (target.signed - start.signed) * eased))
            }
            // Done: changes from outside Luna (keys, Control Center) may reach the slider again.
            if !Task.isCancelled { self?.transition = nil }
        }
    }

    /// A glide is under way.
    var isAnimating: Bool { transition != nil }

    private func update(_ newLevel: Level) {
        var newLevel = newLevel
        if !(xdr && isXDRCapable) { newLevel.boost = 0 }
        if !app.allowDimming { newLevel.dim = 0 }
        level = newLevel
        settings.level = newLevel
        applyBrightness()
    }

    public func setXDR(_ on: Bool) {
        guard isXDRCapable || !on else { return }
        if on == xdr { return }
        // A glide still running (auto brightness) would otherwise carry on to its old target.
        transition?.cancel()
        transition = nil
        if !on, level.boost > 0 { settings.lastBoost = level.boost }
        xdr = on
        settings.xdr = on
        if on {
            update(Level(brightness: 1, boost: max(settings.lastBoost, 0.1)))
        } else {
            update(Level(brightness: 1))
        }
    }

    public func setContrast(_ value: Double) {
        contrast = value.clamped(to: 0...1)
        settings.baseContrast = linksContrast ? contrast / linkedContrastFactor : contrast
        writeDDC(VCP.contrast, contrast)
    }

    public func setVolume(_ value: Double) {
        volume = value.clamped(to: 0...1)
        settings.volume = volume
        if muted, volume > 0 { setMuted(false) }
        writeDDC(VCP.volume, volume)
    }

    public func setMuted(_ mute: Bool) {
        muted = mute
        if hasMute {
            ddc?.write(VCP.mute, value: mute ? 1 : 2)
        } else {
            writeDDC(VCP.volume, mute ? 0 : volume)
        }
    }

    public func selectInput(_ source: InputSource) {
        if settings.inputMethod == .lg {
            ddc?.write(VCP.lgInputSource, value: source.code, source: 0x50)
        } else {
            ddc?.write(VCP.inputSource, value: source.code)
            input = source.code
        }
    }

    // MARK: Settings

    /// Changes this display's settings and applies the result.
    public func updateSettings(_ change: (inout DisplaySettings) -> Void) {
        change(&settings)
        ddc?.timing = settings.slowDDC ? .slow : .normal
        applyBrightness()
    }

    /// Automatic, hardware or software control, from Settings.
    public func setMethod(_ method: ControlMethod) {
        settings.method = method
        switch method {
        case .software:
            control = .software
            applyBrightness()
        case .automatic, .hardware:
            if kind == .builtin || kind == .apple {
                control = AppleNative.canControl(id) ? .apple : .software
                applyBrightness()
            } else if ddc != nil {
                control = .ddc
                Task { await probe() }
            } else {
                // Launched with Software chosen, so no channel was looked for: look now.
                requestDDC?(self)
            }
        }
    }

    /// Dips the brightness so you can see the control working, then asks the monitor what it supports again.
    /// Returns a sentence for Settings.
    public func runTest() async -> String {
        let original = level
        setLevel(Level(brightness: max(0, original.brightness - 0.35)), byUser: false)
        try? await Task.sleep(for: .milliseconds(700))
        setLevel(original, byUser: false)
        switch control {
        case .apple:
            guard ddc != nil else { return "Brightness is controlled by macOS, like the brightness keys." }
            await probe()
            let extras = [hasContrast ? "contrast" : nil, hasVolume ? "volume" : nil, input != nil ? "input" : nil]
                .compactMap { $0 }
            return "Brightness is controlled by macOS"
                + (extras.isEmpty ? "." : "; " + extras.joined(separator: ", ") + " over DDC.")
        case .software:
            return ddc == nil
                ? "Dimmed in software: this display has no DDC connection Luna can use."
                : "Dimmed in software. Choose Hardware under Advanced to keep trying DDC."
        case .preview:
            return "Preview display."
        case .ddc:
            await probe()
            guard control == .ddc else { return "The monitor didn't answer, so Luna dims it in software." }
            if reportsNothing {
                return
                    "The monitor hears DDC but doesn't report its settings. If the brightness dipped just now, hardware control works."
            }
            var parts = [
                hardwareConfirmed ? "brightness" : nil, hasContrast ? "contrast" : nil, hasVolume ? "volume" : nil,
                input != nil ? "input" : nil,
            ]
            .compactMap { $0 }
            if parts.isEmpty { parts = ["commands (it doesn't report values back)"] }
            return "The monitor answers to " + parts.joined(separator: ", ") + "."
        }
    }

    public func resetSettings() {
        let keepLevel = level
        settings = DisplaySettings()
        settings.level = keepLevel
        ddc?.timing = .normal
        setMethod(.automatic)
    }

    // MARK: Applying it

    /// Contrast follows brightness only where Luna drives the backlight over DDC.
    private var linksContrast: Bool { settings.linkContrast && control == .ddc }

    /// Contrast follows brightness down to 60% of its normal value.
    private var linkedContrastFactor: Double { 0.6 + 0.4 * level.brightness }

    private var hardwareBrightness: Double {
        settings.minBrightness + level.brightness * (settings.maxBrightness - settings.minBrightness)
    }

    public var dimMethod: Dimmer.Method {
        switch settings.dimMethod {
        case .gamma: .gamma
        case .overlay: .overlay
        case .automatic: kind == .virtual ? .overlay : .gamma
        }
    }

    /// Pushes the current state to the hardware and overlays again, e.g. after waking.
    public func reapply() {
        applyBrightness()
        if hasVolume, !muted { writeDDC(VCP.volume, volume) }
    }

    func applyBrightness(hardware: Bool = true) {
        switch hardware ? control : .preview {
        case .apple:
            ownWriteUntil = Date().addingTimeInterval(0.5)
            AppleNative.setBrightness(hardwareBrightness, for: id)
        case .ddc:
            writeDDC(VCP.brightness, hardwareBrightness)
            if linksContrast, hasContrast, let base = settings.baseContrast {
                contrast = (base * linkedContrastFactor).clamped(to: 0...1)
                writeDDC(VCP.contrast, contrast)
            }
        case .software, .preview:
            break
        }
        if control != .preview {
            updateBoost()
            applySoftware()
        }
    }

    /// Dimming below 0% and the XDR lift share the colour table: one factor for both.
    private func applySoftware() {
        let factor = SoftwareDimming.factor(level, hardware: control != .software) * gammaBoost
        Dimmer.shared.set(factor, for: id, method: dimMethod)
    }

    /// XDR: brighter than 100% by lifting the display's colour table into its HDR headroom. The table is applied
    /// by the display pipeline after macOS has composited everything, so the boost holds through Space swipes,
    /// Mission Control and full-screen video (Netflix), which an overlay can't reach. Displays without a
    /// colour table (AirPlay, DisplayLink) fall back to the multiply overlay.
    private func updateBoost() {
        guard xdr, isXDRCapable, level.boost > 0.001, let screen = NSScreen.with(displayID: id) else {
            stopBoost()
            return
        }
        // Past ~3.2× highlights clip and colours wash out, even where the panel has more headroom.
        let multiplier = xdrMultiplier

        guard dimMethod == .gamma, Dimmer.shared.hasColourTable(id) else {
            gammaBoost = 1
            if let edr {
                edr.multiplier = multiplier
            } else {
                edr = EDROverlay(screen: screen, multiplier: multiplier)
            }
            return
        }
        edr?.close()
        edr = nil

        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        // An XDR panel opens its headroom while HDR content is on screen, as far as that content asks for: the
        // trigger is that content.
        if headroom < multiplier - 0.05, edrTrigger == nil {
            edrTrigger = EDRTrigger(
                screen: screen, value: multiplier, avoidingCorner: app.roundedCorners ? app.cornerRadius * 1.6 : 0)
        }
        edrTrigger?.value = multiplier
        // The table works on gamma-encoded values, so the lift for a given gain in light is its 2.2th root.
        gammaBoost = headroom > 1.05 ? pow(min(multiplier, headroom), 1 / 2.2) : 1
        startBoostWatch()
    }

    /// macOS resets colour tables now and then (waking, display changes, some full-screen video) and the
    /// headroom moves with the backlight; checking every second brings a lost boost back within a moment.
    private func startBoostWatch() {
        guard boostWatch == nil else { return }
        boostWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBoost() }
        }
    }

    private func refreshBoost() {
        let before = gammaBoost
        updateBoost()
        if abs(gammaBoost - before) > 0.001 {
            applySoftware()
        } else {
            Dimmer.shared.restoreIfReset(id)
        }
    }

    private func stopBoost() {
        boostWatch?.invalidate()
        boostWatch = nil
        edrTrigger?.close()
        edrTrigger = nil
        edr?.close()
        edr = nil
        gammaBoost = 1
    }

    /// Brightness goes over DDC only when DDC drives the backlight. Volume, contrast and input go whenever the
    /// monitor has a channel, whatever controls its brightness (macOS, or software dimming).
    private func writeDDC(_ vcp: UInt8, _ fraction: Double) {
        guard let ddc, vcp != VCP.brightness || control == .ddc else { return }
        let maximum = Double(ddcMaximum[vcp] ?? 100)
        ddc.write(vcp, value: UInt16((fraction.clamped(to: 0...1) * maximum).rounded()))
    }

    /// The built-in or Apple display's brightness changed outside Luna (keys, Control Center, ambient light).
    func systemBrightnessChanged(_ value: Double) {
        guard transition == nil, level.dim == 0, level.boost == 0, Date() > ownWriteUntil else { return }
        let range = settings.maxBrightness - settings.minBrightness
        level = Level(brightness: range > 0 ? (value - settings.minBrightness) / range : value)
        settings.level = level
    }

    func detach() {
        transition?.cancel()
        stopBoost()
        Dimmer.shared.reset(id)
    }

    func screenChanged() {
        guard let screen = NSScreen.with(displayID: id) else { return }
        edrHeadroom = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        edr?.move(to: screen)
        edrTrigger?.move(to: screen)
    }

    // MARK: Finding out what the monitor can do

    /// Reads the monitor's current values over DDC. A monitor that answers nothing is dimmed in software
    /// instead (unless Settings says to keep trying hardware).
    func probe() async {
        guard let ddc, control == .ddc || control == .apple else { return }
        // Over DDC, brightness too; for displays macOS controls, only the extras.
        let ddcBrightness = control == .ddc
        probing = true
        touchedDuringProbe = false
        defer { probing = false }

        var responsive = false
        func read(_ vcp: UInt8) async -> (current: Double, maximum: UInt16)? {
            let reply = await ddc.read(vcp)
            if reply != .invalid { responsive = true }
            guard case let .value(current, maximum) = reply, maximum > 0 else { return nil }
            ddcMaximum[vcp] = maximum
            return (Double(current) / Double(maximum), maximum)
        }

        let brightness = ddcBrightness ? await read(VCP.brightness) : nil
        hardwareConfirmed = brightness != nil || control == .apple
        if let brightness, !touchedDuringProbe, level.dim == 0, level.boost == 0 {
            let range = settings.maxBrightness - settings.minBrightness
            let normal = range > 0 ? (brightness.current - settings.minBrightness) / range : brightness.current
            level = Level(brightness: normal)
            settings.level = level
        }
        if let contrast = await read(VCP.contrast) {
            hasContrast = true
            self.contrast = contrast.current
            if settings.baseContrast == nil {
                settings.baseContrast = linksContrast ? contrast.current / linkedContrastFactor : contrast.current
            }
        }
        if let volume = await read(VCP.volume) {
            hasVolume = true
            if settings.volume == nil || !touchedDuringProbe { self.volume = volume.current }
        }
        let muteReply = await ddc.read(VCP.mute)
        if case let .value(current, _) = muteReply {
            hasMute = true
            muted = current == 1
        }
        let inputReply = await ddc.read(VCP.inputSource)
        if case let .value(current, _) = inputReply {
            input = current & 0xFF
        }
        if muteReply != .invalid || inputReply != .invalid { responsive = true }
        ddcResponsive = responsive

        let answered = brightness != nil || hasContrast || hasVolume || hasMute || input != nil
        hasInput = answered
        // A monitor that doesn't answer at all is dimmed in software. One that answers with null messages
        // keeps hardware control: those usually obey writes even though they won't report values.
        if !responsive, settings.method == .automatic, control == .ddc {
            control = .software
        }
        let found = [
            brightness.map { "brightness \(Int($0.current * 100))% of \($0.maximum)" }, hasContrast ? "contrast" : nil,
            hasVolume ? "volume" : nil, hasMute ? "mute" : nil,
            input.flatMap(InputSource.name(for:)).map { "input \($0)" },
        ].compactMap { $0 }
        let summary =
            !found.isEmpty
            ? found.joined(separator: ", ")
            : responsive ? "null messages (it hears DDC but doesn't report values)" : "nothing"
        NSLog("Luna: %@ answered DDC with %@; brightness via %@", name, summary, control.label)
        applyBrightness()
    }
}

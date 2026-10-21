import AppKit
import ApplicationServices
import LunaCore

/// The keyboard's brightness and volume keys, for every display.
///
/// An event tap sees the media keys before macOS does (which needs Accessibility). Keys for a display macOS
/// already handles (the built-in screen in its normal range) pass straight through; the rest are handled
/// here and swallowed, with Luna's own indicator. Tap technique as in MonitorControl/MediaKeyTap (MIT).
final class KeyController {
    enum MediaKey: Int {
        case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    private let model: AppModel
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowing = Set<Int>()
    private var accessPoll: Timer?
    private var accessPollRemaining = 0

    init(model: AppModel) {
        self.model = model
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The setting changes a moment after the notification.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.start()
            }
        }
    }

    private var controller: DisplayController { model.controller }
    private var settings: AppSettings { model.settings }

    /// Starts the tap if Accessibility allows it; harmless to call again.
    func start() {
        let trusted = AXIsProcessTrusted()
        model.keysEnabled = trusted
        guard trusted else {
            stop()
            return
        }
        if let tap, CGEvent.tapIsEnabled(tap: tap) { return }
        stop()
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue)  // NX_SYSDEFINED
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: keyTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Shows macOS's Accessibility prompt, then starts as soon as it's granted.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary  // kAXTrustedCheckOptionPrompt
        if AXIsProcessTrustedWithOptions(options) {
            start()
            return
        }
        accessPoll?.invalidate()
        accessPollRemaining = 180
        accessPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollAccess() }
        }
    }

    private func pollAccess() {
        accessPollRemaining -= 1
        guard AXIsProcessTrusted() || accessPollRemaining <= 0 else { return }
        accessPoll?.invalidate()
        accessPoll = nil
        start()
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when Luna handled the event and macOS shouldn't see it.
    fileprivate func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .keyDown {
            // F14/F15 are the brightness keys on keyboards without media keys.
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            guard modifiers.isEmpty, code == 107 || code == 113 else { return false }
            return brightness(up: code == 113, fine: false)
        }

        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return false }
        let data = nsEvent.data1
        guard let key = MediaKey(rawValue: (data & 0xFFFF_0000) >> 16) else { return false }
        let isDown = (data & 0xFF00) >> 8 == 0xA
        // Holding ⌥⇧ gives quarter steps, as on macOS.
        let fine = nsEvent.modifierFlags.contains([.option, .shift])

        guard isDown else { return swallowing.remove(key.rawValue) != nil }
        let handled: Bool
        switch key {
        case .brightnessUp: handled = brightness(up: true, fine: fine)
        case .brightnessDown: handled = brightness(up: false, fine: fine)
        case .volumeUp, .volumeDown, .mute: handled = volume(key, fine: fine)
        }
        if handled { swallowing.insert(key.rawValue) }
        return handled
    }

    // MARK: Brightness

    private var brightnessTargets: [Display] {
        switch settings.keysTarget {
        case .pointer: controller.displayUnderPointer.map { [$0] } ?? []
        case .all: controller.displays
        case .main: controller.mainDisplay.map { [$0] } ?? []
        }
    }

    @discardableResult
    func brightness(up: Bool, fine: Bool) -> Bool {
        var handled = false
        for display in brightnessTargets {
            let allowBoost = settings.keysEnterXDR && display.isXDRCapable
            if leavesToSystem(display, up: up, allowBoost: allowBoost) { continue }
            let next = SliderZones.step(
                display.level, by: (up ? 1 : -1) * (fine ? 0.25 : 1), allowDimming: settings.allowDimming,
                allowBoost: allowBoost)
            if next.boost > 0, !display.xdr { display.setXDR(true) }
            display.setLevel(next)
            showBrightnessHUD(display)
            handled = true
        }
        return handled
    }

    /// macOS handles its own displays in the normal range, with its own indicator; Luna steps in past the ends.
    private func leavesToSystem(_ display: Display, up: Bool, allowBoost: Bool) -> Bool {
        guard display.control == .apple, display.level.dim == 0, display.level.boost == 0 else { return false }
        if up, display.level.brightness >= 0.999, allowBoost { return false }
        if !up, display.level.brightness <= 0.001, settings.allowDimming { return false }
        return true
    }

    func showBrightnessHUD(_ display: Display) {
        let level = display.level
        let icon = level.dim > 0 ? "moon.fill" : level.boost > 0 ? "sun.max.fill" : "sun.max"
        let tone: GlassSlider.Tone = level.dim > 0 ? .dim : level.boost > 0 ? .boost : .normal
        let label: String
        let value: Double
        if level.dim > 0 {
            label = "−\(Int((level.dim * 100).rounded()))%"
            value = 1 - level.dim
        } else if level.boost > 0 {
            label = "XDR"
            value = level.boost
        } else {
            label = "\(Int((level.brightness * 100).rounded()))%"
            value = level.brightness
        }
        HUD.shared.show(on: display.id, icon: icon, value: value, label: label, tone: tone)
    }

    // MARK: Volume

    /// Only when sound goes to a monitor macOS can't set the volume of (HDMI and DisplayPort audio).
    private func volume(_ key: MediaKey, fine: Bool) -> Bool {
        guard settings.controlVolumeKeys, let output = AudioOutput.current(), output.isDisplayAudio,
            !output.canSetVolume
        else { return false }
        let candidates = controller.displays.filter(\.offersVolume)
        let named = candidates.first {
            output.name.localizedCaseInsensitiveContains($0.systemName)
                || $0.systemName.localizedCaseInsensitiveContains(output.name)
        }
        let pointer = controller.displayUnderPointer.flatMap { display in
            candidates.contains { $0 === display } ? display : nil
        }
        guard let display = named ?? pointer ?? candidates.first else { return false }

        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .volumeUp: display.setVolume(display.volume + step)
        case .volumeDown: display.setVolume(display.volume - step)
        default: display.setMuted(!display.muted)
        }
        let muted = display.muted || display.volume == 0
        HUD.shared.show(
            on: display.id, icon: muted ? "speaker.slash.fill" : "speaker.wave.3.fill",
            value: muted ? 0 : display.volume,
            label: muted ? "Muted" : "\(Int((display.volume * 100).rounded()))")
        return true
    }
}

// A C callback, so not isolated to the main actor; the tap's run loop source is on the main run loop, though.
nonisolated private func keyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) let context = refcon
    let swallow = MainActor.assumeIsolated {
        let controller = Unmanaged<KeyController>.fromOpaque(context).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            controller.reenable()
            return false
        }
        return controller.handle(event, type: type)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

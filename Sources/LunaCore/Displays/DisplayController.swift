import AppKit
import CPrivate
import CoreGraphics
import Observation

/// A display Luna turned off, kept so it can be turned back on.
public struct DisabledDisplay: Identifiable, Equatable, Sendable {
    public var id: CGDirectDisplayID
    public var name: String
}

/// Knows which displays are connected and keeps Luna's controls, dimming and overlays in step with them
/// through hot-plugs, sleep and wake.
@MainActor @Observable
public final class DisplayController {
    public private(set) var displays: [Display] = []
    public private(set) var disabled: [DisabledDisplay] = []
    public let settings: AppSettings
    public let isPreview: Bool

    @ObservationIgnored public let store: DisplayStore
    @ObservationIgnored public private(set) var auto: AutoBrightness!
    @ObservationIgnored private let corners = CornerMask()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var brightnessObservers: [CGDirectDisplayID: BrightnessObserver] = [:]

    public init(settings: AppSettings, store: DisplayStore = DisplayStore(), preview: [PreviewDisplay]? = nil) {
        self.settings = settings
        self.store = store
        isPreview = preview != nil
        auto = AutoBrightness(controller: self)
        if let preview {
            displays = preview.enumerated().map { $1.makeDisplay(index: $0, app: settings, store: store) }
        }
    }

    // MARK: Lifecycle

    public func start() {
        guard !isPreview else { return }
        // Clear any dimming a previous run left behind (if it didn't quit cleanly).
        CGDisplayRestoreColorSyncSettings()
        for id in settings.disabledDisplays { DisplayPower.setEnabled(true, display: id) }
        settings.disabledDisplays = []

        DisplayControllerRegistry.current = self
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil)
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main)
            {
                _ in MainActor.assumeIsolated { self.scheduleRefresh() }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.didWake() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.didWake() }
            },
        ]
        refresh()
        updateCorners()
    }

    /// Leaves every display as macOS would have it: undimmed, no overlays, nothing turned off.
    public func stop() {
        for display in displays { display.detach() }
        Dimmer.shared.resetAll()
        corners.hide()
        for item in disabled { DisplayPower.setEnabled(true, display: item.id) }
        settings.disabledDisplays = []
        auto.stop()
        for observer in brightnessObservers.values { observer.stop() }
        brightnessObservers.removeAll()
        store.flush()
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func didWake() {
        for display in displays { display.ddc?.pause(for: 3) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            refresh()
            Dimmer.shared.reapply()
            for display in displays { display.reapply() }
            auto.update()
        }
    }

    // MARK: Finding displays

    public func refresh() {
        guard !isPreview else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return }
        let active = ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }

        var next: [Display] = []
        var added: [Display] = []
        for id in active {
            if let existing = displays.first(where: { $0.id == id }) {
                next.append(existing)
            } else if let display = makeDisplay(id) {
                next.append(display)
                added.append(display)
            }
        }
        for gone in displays where !next.contains(where: { $0 === gone }) { gone.detach() }

        // DDC channels are matched to displays all at once: matching weighs every pair. Apple-controlled
        // external monitors get one too, for contrast, volume and input; their brightness stays with macOS.
        let needDDC = next.filter {
            ($0.kind == .external || $0.kind == .apple) && $0.ddc == nil && $0.settings.method != .software
        }
        if !needDDC.isEmpty {
            let channels = DDCDiscovery.channels(for: needDDC.map { ($0.id, $0.identity) })
            for display in needDDC {
                if let channel = channels[display.id] {
                    display.ddc = channel
                    if display.kind == .external { display.control = .ddc }
                }
            }
        }

        displays = next.sorted(by: Self.order)
        for display in added {
            NSLog(
                "Luna: found %@ (%@, id %u, vendor %04X, product %04X)%@", display.name, display.kind.rawValue,
                display.id,
                display.identity.vendor ?? 0, display.identity.product ?? 0,
                display.ddc != nil ? " with a DDC channel" : "")
        }
        disabled.removeAll { item in active.contains(item.id) }
        for display in displays { display.screenChanged() }
        for display in added {
            display.onUserBrightness = { [weak self] display in self?.auto.userAdjusted(display) }
            // Start from where the display is now: macOS's value for Apple displays, the monitor's own
            // (read by `probe`) over DDC. Only the software parts (dimming, XDR) are restored at once.
            if display.control == .apple, let value = AppleNative.brightness(display.id) {
                display.systemBrightnessChanged(value)
            }
            display.applyBrightness(hardware: false)
            Task { await display.probe() }
        }
        observeSystemBrightness()
        updateCorners()
        auto.update()
    }

    /// Keeps Apple displays' sliders in step with the brightness keys and Control Center, and feeds "Match Mac".
    private func observeSystemBrightness() {
        let apple = Set(displays.filter { $0.control == .apple }.map(\.id))
        for (id, observer) in brightnessObservers where !apple.contains(id) {
            observer.stop()
            brightnessObservers[id] = nil
        }
        for display in displays where display.control == .apple && brightnessObservers[display.id] == nil {
            brightnessObservers[display.id] = BrightnessObserver(display: display.id) {
                [weak self, weak display] value in
                guard let self, let display else { return }
                display.systemBrightnessChanged(value)
                if display === self.syncSource { self.auto.sourceChanged(value) }
            }
        }
    }

    private func makeDisplay(_ id: CGDirectDisplayID) -> Display? {
        let uuid: String = {
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
            return CFUUIDCreateString(nil, cfUUID) as String
        }()
        let info = (LunaCoreDisplayCreateInfoDictionary(id) as NSDictionary?) as? [String: Any] ?? [:]
        var identity = DisplayIdentity(info: info)
        if identity.vendor == nil { identity.vendor = Int(CGDisplayVendorNumber(id)) }
        if identity.product == nil { identity.product = Int(CGDisplayModelNumber(id)) }
        if identity.serial == nil { identity.serial = Int(CGDisplaySerialNumber(id)) }

        let screenName = NSScreen.with(displayID: id)?.localizedName
        let name = screenName ?? identity.name ?? "Display"
        let kind: DisplayKind
        if CGDisplayIsBuiltin(id) != 0 {
            kind = .builtin
        } else if AppleNative.canControl(id) {
            kind = .apple
        } else if Self.looksVirtual(name: name, info: info) {
            kind = .virtual
        } else {
            kind = .external
        }

        let method = store[uuid].method
        let control: Control =
            switch kind {
            case .builtin, .apple: method == .software ? .software : .apple
            case .external, .virtual: .software
            }
        return Display(
            id: id, uuid: uuid, name: name, kind: kind, identity: identity, control: control, app: settings,
            store: store)
    }

    private static func looksVirtual(name: String, info: [String: Any]) -> Bool {
        if (info["kCGDisplayIsAirPlay"] as? Bool) == true || (info["kCGDisplayIsVirtualDevice"] as? Bool) == true {
            return true
        }
        let lower = name.lowercased()
        return ["sidecar", "ipad", "airplay", "virtual", "displaylink", "dummy", "luna display"].contains {
            lower.contains($0)
        }
    }

    /// Built-in first, then left to right as arranged in System Settings.
    private static func order(_ a: Display, _ b: Display) -> Bool {
        if (a.kind == .builtin) != (b.kind == .builtin) { return a.kind == .builtin }
        let ax = NSScreen.with(displayID: a.id)?.frame.minX ?? 0
        let bx = NSScreen.with(displayID: b.id)?.frame.minX ?? 0
        return ax != bx ? ax < bx : a.id < b.id
    }

    // MARK: Queries

    /// The display the brightness keys should change: under the pointer, or the main one.
    public var displayUnderPointer: Display? {
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
            let id = screen.displayID, let display = displays.first(where: { $0.id == id })
        {
            return display
        }
        return mainDisplay
    }

    public var mainDisplay: Display? {
        displays.first { $0.id == CGMainDisplayID() } ?? displays.first
    }

    /// The display "Match Mac" follows: the built-in one, else an Apple monitor.
    public var syncSource: Display? {
        displays.first { $0.kind == .builtin && $0.control == .apple }
            ?? displays.first { $0.kind == .apple && $0.control == .apple }
    }

    public var canSync: Bool { syncSource != nil && displays.count > 1 }

    // MARK: All displays

    /// The "All displays" slider: the average position, and moving it moves every display.
    public var averagePosition: Double {
        guard !displays.isEmpty else { return 0 }
        return displays.map(\.position).reduce(0, +) / Double(displays.count)
    }

    public func setAllPositions(_ position: Double) {
        for display in displays { display.setPosition(position) }
    }

    // MARK: Turning displays off

    /// Only with another display left to show things on.
    public func canTurnOff(_ display: Display) -> Bool {
        !isPreview && displays.count > 1 && DisplayPower.isAvailable
    }

    public func turnOff(_ display: Display) {
        guard canTurnOff(display) else { return }
        let item = DisabledDisplay(id: display.id, name: display.name)
        display.detach()
        if DisplayPower.setEnabled(false, display: display.id) {
            disabled.append(item)
            settings.disabledDisplays.append(item.id)
            scheduleRefresh()
        }
    }

    public func turnOn(_ item: DisabledDisplay) {
        DisplayPower.setEnabled(true, display: item.id)
        disabled.removeAll { $0.id == item.id }
        settings.disabledDisplays.removeAll { $0 == item.id }
        scheduleRefresh()
    }

    // MARK: Rounded corners

    public func updateCorners() {
        guard !isPreview else { return }
        if settings.roundedCorners {
            corners.show(radius: settings.cornerRadius)
        } else {
            corners.hide()
        }
    }
}

private func displayReconfigured(
    _ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?
) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    Task { @MainActor in DisplayControllerRegistry.current?.scheduleRefresh() }
}

/// The reconfiguration callback is a C function, so it finds the controller here.
@MainActor
enum DisplayControllerRegistry {
    static weak var current: DisplayController?
}

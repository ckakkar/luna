import Foundation
import Observation

public enum AutoMode: String, Codable, CaseIterable, Sendable {
    case off
    /// Follow the built-in (or Apple) display's brightness.
    case sync
    /// Follow daylight where you are.
    case sun
}

/// Which display the brightness keys change.
public enum KeysTarget: String, Codable, CaseIterable, Sendable {
    case pointer, all, main
}

public enum ControlMethod: String, Codable, CaseIterable, Sendable {
    case automatic, hardware, software
}

public enum DimMethod: String, Codable, CaseIterable, Sendable {
    case automatic, gamma, overlay
}

public enum InputMethod: String, Codable, CaseIterable, Sendable {
    case standard, lg
}

/// Everything Luna remembers about one display, keyed by the display's UUID.
public struct DisplaySettings: Codable, Equatable, Sendable {
    public var nickname: String?
    /// Contrast follows brightness (down to 60% of `baseContrast` at 0%), for deeper dimming.
    public var linkContrast = true
    /// Brightness limits as fractions of the monitor's own range.
    public var minBrightness = 0.0
    public var maxBrightness = 1.0
    public var method = ControlMethod.automatic
    public var slowDDC = false
    public var inputMethod = InputMethod.standard
    public var dimMethod = DimMethod.automatic
    public var showVolume = true
    /// For monitors that answer DDC without reporting values: offer contrast, volume and input anyway.
    public var showAllControls = false

    public var level: Level?
    public var baseContrast: Double?
    public var volume: Double?
    public var xdr = false
    /// The XDR boost to come back to when XDR is switched on again.
    public var lastBoost = 0.5

    public var syncCurve = Curve(from: 0, to: 1)
    public var sunCurve = Curve(from: 0.35, to: 0.9)

    public init() {}
}

/// A global shortcut: a key code with Carbon modifier flags.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    case brightnessUp, brightnessDown, toggleXDR, toggleCorners
}

public struct SavedLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Guessed from the time zone because Location access wasn't given.
    public var approximate: Bool

    public init(latitude: Double, longitude: Double, approximate: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.approximate = approximate
    }
}

/// App-wide settings, saved to UserDefaults as they change.
@MainActor @Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var autoMode: AutoMode { didSet { save(autoMode, "autoMode") } }
    public var roundedCorners: Bool { didSet { save(roundedCorners, "roundedCorners") } }
    public var cornerRadius: Double { didSet { save(cornerRadius, "cornerRadius") } }
    public var keysTarget: KeysTarget { didSet { save(keysTarget, "keysTarget") } }
    public var allowDimming: Bool { didSet { save(allowDimming, "allowDimming") } }
    public var keysEnterXDR: Bool { didSet { save(keysEnterXDR, "keysEnterXDR") } }
    public var controlVolumeKeys: Bool { didSet { save(controlVolumeKeys, "controlVolumeKeys") } }
    public var hasOnboarded: Bool { didSet { save(hasOnboarded, "hasOnboarded") } }
    public var dismissedKeysBanner: Bool { didSet { save(dismissedKeysBanner, "dismissedKeysBanner") } }
    public var location: SavedLocation? { didSet { save(location, "location") } }
    public var shortcuts: [ShortcutAction: KeyCombo] { didSet { save(shortcuts, "shortcuts") } }
    /// Displays Luna turned off, to turn back on at quit or next launch.
    public var disabledDisplays: [UInt32] { didSet { save(disabledDisplays, "disabledDisplays") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = defaults.data(forKey: key) else { return fallback }
            return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
        }
        autoMode = load("autoMode", .off)
        roundedCorners = load("roundedCorners", false)
        cornerRadius = load("cornerRadius", 12)
        keysTarget = load("keysTarget", .pointer)
        allowDimming = load("allowDimming", true)
        keysEnterXDR = load("keysEnterXDR", true)
        controlVolumeKeys = load("controlVolumeKeys", true)
        hasOnboarded = load("hasOnboarded", false)
        dismissedKeysBanner = load("dismissedKeysBanner", false)
        location = load("location", nil)
        shortcuts = load("shortcuts", [:])
        disabledDisplays = load("disabledDisplays", [])
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

/// Per-display settings, saved shortly after they change (a slider drag changes them many times a second).
@MainActor
public final class DisplayStore {
    private let defaults: UserDefaults
    private var all: [String: DisplaySettings]
    private var pendingSave: Task<Void, Never>?
    private static let key = "displays"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        all = [:]
        guard let data = defaults.data(forKey: Self.key),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        for (key, value) in raw {
            if let settings = Self.decodeMergingDefaults(value) { all[key] = settings }
        }
    }

    public subscript(key: String) -> DisplaySettings {
        get { all[key] ?? DisplaySettings() }
        set {
            all[key] = newValue
            scheduleSave()
        }
    }

    public func forgetLearnedCurves() {
        for key in all.keys {
            all[key]?.syncCurve = DisplaySettings().syncCurve
            all[key]?.sunCurve = DisplaySettings().sunCurve
        }
        scheduleSave()
    }

    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.key) }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Decodes saved settings over the current defaults, so settings added in later versions get their
    /// default instead of making the whole entry unreadable.
    nonisolated static func decodeMergingDefaults(_ saved: Any) -> DisplaySettings? {
        guard let saved = saved as? [String: Any],
            let defaultsData = try? JSONEncoder().encode(DisplaySettings()),
            var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return nil }
        merged.merge(saved) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(DisplaySettings.self, from: data)
    }
}

import AppKit
import ServiceManagement
import Sparkle

/// Open at login, through macOS's Login Items.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    /// The user has to allow Luna in System Settings › General › Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                // register() isn't idempotent: it adds a second entry when called again.
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            NSLog("Luna: couldn't change Open at login: \(error.localizedDescription)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Sparkle updates. Only builds that carry an update key (releases) check; local builds don't.
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        if !key.isEmpty, !feed.isEmpty {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

enum AppInfo {
    /// The full-colour artwork. `NSApp.applicationIconImage` follows the system's icon style, which may be
    /// tinted or clear; Luna's own windows show the real thing.
    static var icon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static let repository = URL(string: "https://github.com/ckakkar/luna")!
    static let issues = URL(string: "https://github.com/ckakkar/luna/issues/new")!
    static let credits = URL(string: "https://github.com/ckakkar/luna/blob/main/CREDITS.md")!
    static let usage = URL(string: "https://github.com/ckakkar/luna/blob/main/USAGE.md")!
}

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

/// Updates, like Trav's: Luna checks GitHub soon after it opens and then every hour, shows what changed, and
/// installs and relaunches. Only builds that carry an update key (releases) check; local builds don't.
///
/// A menu bar app shouldn't throw a window in front of whatever you're doing, so an update found by a
/// background check is announced gently (a dot on the menu bar moon and a card in the panel) and Sparkle's
/// window opens when you click it. One found right after launch shows Sparkle's window at once.
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?
    /// Called with the new version when one is waiting, and nil once it's dealt with.
    var onAvailable: (String?) -> Void = { _ in }
    private var announcedAt: Date?

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        guard !key.isEmpty, !feed.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)

        // Sparkle's own schedule waits a full interval after the last check; check soon after launch too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let updater = self?.controller?.updater, updater.automaticallyChecksForUpdates,
                updater.canCheckForUpdates
            else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var isAvailable: Bool { controller != nil }

    /// Opens Sparkle's window: the waiting update with its notes, or a fresh check.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

// Sparkle calls its user driver delegate on the main thread.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Right after launch, or if the dot has been ignored for a day, show the window itself.
        immediateFocus || (announcedAt.map { Date().timeIntervalSince($0) > 86400 } ?? false)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            if announcedAt == nil { announcedAt = Date() }
            onAvailable(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        announcedAt = nil
        onAvailable(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        announcedAt = nil
        onAvailable(nil)
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

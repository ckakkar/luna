import AppKit
import LunaCore
import Observation

/// What the windows share: the displays, settings, and the app-level actions they can trigger.
@Observable
final class AppModel {
    let controller: DisplayController
    let updater: Updater
    /// Accessibility is granted, so the brightness and volume keys work.
    var keysEnabled = false
    /// A newer Luna found by a background check, waiting to be installed.
    var availableUpdate: String?
    /// `--preview --expanded`: cards start with their extra options showing.
    @ObservationIgnored var previewExpanded = false

    @ObservationIgnored var openSettings: (SettingsPane) -> Void = { _ in }
    @ObservationIgnored var closePanel: () -> Void = {}
    @ObservationIgnored var enableKeys: () -> Void = {}
    @ObservationIgnored var settingsSelection: ((SettingsPane, CGDirectDisplayID?) -> Void)?

    init(controller: DisplayController, updater: Updater) {
        self.controller = controller
        self.updater = updater
        updater.onAvailable = { [weak self] version in self?.availableUpdate = version }
    }

    var settings: AppSettings { controller.settings }

    func setAutoMode(_ mode: AutoMode) {
        settings.autoMode = mode
        controller.auto.update()
    }

    func setRoundedCorners(_ on: Bool) {
        settings.roundedCorners = on
        controller.updateCorners()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

enum SettingsPane: Hashable {
    case general, displays(CGDirectDisplayID?), auto, keyboard, about

    var id: String {
        switch self {
        case .general: "general"
        case .displays: "displays"
        case .auto: "auto"
        case .keyboard: "keyboard"
        case .about: "about"
        }
    }
}

/// An `NSMenu` popped up from a SwiftUI button, so menus keep the panel's own button styles.
enum PopUpMenu {
    struct Item {
        var title: String
        var symbol: String? = nil
        var checked = false
        var enabled = true
        var action: @MainActor () -> Void = {}
        var isSeparator = false

        static let separator = Item(title: "", isSeparator: true)
    }

    static func show(_ items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let menuItem = ClosureMenuItem(title: item.title, handler: item.action)
            menuItem.state = item.checked ? .on : .off
            menuItem.isEnabled = item.enabled
            if let symbol = item.symbol {
                menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // NSMenuItem's initializers aren't main-actor isolated, so neither is this subclass; menus only ever
    // run it on the main thread.
    nonisolated private final class ClosureMenuItem: NSMenuItem {
        private let handler: @MainActor () -> Void

        init(title: String, handler: @escaping @MainActor () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(run), keyEquivalent: "")
            target = self
        }

        required init(coder: NSCoder) { fatalError("not used") }

        @objc private func run() {
            let handler = self.handler
            MainActor.assumeIsolated { handler() }
        }
    }
}

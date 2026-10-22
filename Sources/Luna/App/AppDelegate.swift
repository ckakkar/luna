import AppKit
import LunaCore
import Observation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var settingsWindow: SettingsWindowController!
    private var welcome: WelcomeWindowController?
    private var keys: KeyController!
    private var signalSources: [DispatchSourceSignal] = []
    private var glyphTimer: Timer?
    private var backdrop: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions(arguments: CommandLine.arguments)
        if let appearance = options.appearance { NSApp.appearance = NSAppearance(named: appearance) }

        let settings: AppSettings
        let controller: DisplayController
        if options.preview {
            let defaults = UserDefaults(suiteName: "xyz.kkrwhofrags.luna.preview")!
            defaults.removePersistentDomain(forName: "xyz.kkrwhofrags.luna.preview")
            settings = AppSettings(defaults: defaults)
            settings.autoMode = options.autoMode
            settings.roundedCorners = true
            let samples = Array(PreviewDisplay.samples.suffix(options.displayCount))
            controller = DisplayController(
                settings: settings, store: DisplayStore(defaults: defaults), preview: samples)
        } else {
            settings = AppSettings()
            controller = DisplayController(settings: settings)
        }

        model = AppModel(controller: controller, updater: Updater())
        model.previewExpanded = options.expanded
        if options.preview, options.showUpdate { model.availableUpdate = "0.2.0" }
        panel = PanelController(model: model)
        settingsWindow = SettingsWindowController(model: model)
        keys = KeyController(model: model)
        installMainMenu()

        model.openSettings = { [weak self] pane in
            self?.panel.hide()
            self?.settingsWindow.show(pane)
        }
        model.closePanel = { [weak self] in self?.panel.hide() }
        model.enableKeys = { [weak self] in self?.keys.requestAccess() }

        HotKeys.shared.onAction = { [weak self] action in self?.perform(action) }
        HotKeys.shared.register(settings.shortcuts)

        controller.start()
        if !options.preview { keys.start() }
        watchSignals()

        glyphTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.updateGlyph() }
        }

        if options.selfTest {
            let test = SelfTest(model: model, panel: panel, keys: keys, settingsWindow: settingsWindow)
            Task { await test.run() }
            return
        }

        if options.preview {
            if options.showSettings {
                settingsWindow.show(options.pane)
            } else if options.showWelcome {
                showWelcome()
            } else {
                panel.pinned = true
                panel.show(centeredOn: NSScreen.main)
                if options.backdrop { showBackdrop() }
            }
            if options.showHUD, let display = controller.displays.last {
                // Late enough for a screenshot taken a few seconds after launch to catch it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    self?.keys.showBrightnessHUD(display)
                }
            }
        } else if options.quiet {
            // Nothing on screen but the menu bar icon (scripted runs, like the update test).
        } else if !settings.hasOnboarded && !options.openPanel {
            showWelcome()
        } else if options.openPanel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.panel.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.controller.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening Luna again (from Finder or Spotlight) shows the panel.
        panel.show()
        return false
    }

    /// `--preview --backdrop`: a twilight gradient behind the panel, so screenshots show the glass over
    /// something without showing anyone's desktop.
    private func showBackdrop() {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 560, height: 980)
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
            width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue - 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Backdrop())
        window.orderFrontRegardless()
        backdrop = window
    }

    private func showWelcome() {
        let welcome = WelcomeWindowController(model: model)
        welcome.onFinish = { [weak self] in
            self?.welcome = nil
            self?.panel.show()
        }
        self.welcome = welcome
        welcome.show()
    }

    private func perform(_ action: ShortcutAction) {
        let controller = model.controller
        switch action {
        case .brightnessUp: keys.brightness(up: true, fine: false)
        case .brightnessDown: keys.brightness(up: false, fine: false)
        case .toggleXDR:
            guard let display = controller.displayUnderPointer, display.isXDRCapable else { return }
            display.setXDR(!display.xdr)
            keys.showBrightnessHUD(display)
        case .toggleCorners:
            model.setRoundedCorners(!model.settings.roundedCorners)
        }
    }

    /// Quitting from a terminal (Ctrl-C) or `kill` still puts the displays back.
    private func watchSignals() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    /// The menus a window needs to respond to ⌘W, ⌘Q and copy and paste, though Luna has no menu bar of its own.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Luna", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Luna", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Luna", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func showAbout() { model.openSettings(.about) }
    @objc private func showSettings() { model.openSettings(.general) }
}

/// Command-line options, mostly for `make preview`.
struct LaunchOptions {
    var preview = false
    var appearance: NSAppearance.Name?
    var displayCount = 2
    var autoMode = AutoMode.off
    var showSettings = false
    var showWelcome = false
    var showHUD = false
    var expanded = false
    var pane = SettingsPane.general
    /// Opens the panel under the menu bar icon at launch.
    var openPanel = false
    var backdrop = false
    var showUpdate = false
    var selfTest = false
    var quiet = false

    init(arguments: [String]) {
        preview = arguments.contains("--preview")
        if arguments.contains("--dark") { appearance = .darkAqua }
        if arguments.contains("--light") { appearance = .aqua }
        if let index = arguments.firstIndex(of: "--displays"), index + 1 < arguments.count,
            let count = Int(arguments[index + 1])
        {
            displayCount = min(max(count, 1), PreviewDisplay.samples.count)
        }
        if arguments.contains("--sun") { autoMode = .sun }
        showSettings = arguments.contains("--settings")
        showWelcome = arguments.contains("--welcome")
        showHUD = arguments.contains("--hud")
        expanded = arguments.contains("--expanded")
        openPanel = arguments.contains("--open")
        backdrop = arguments.contains("--backdrop")
        showUpdate = arguments.contains("--update")
        selfTest = arguments.contains("--self-test")
        quiet = arguments.contains("--quiet")
        if let index = arguments.firstIndex(of: "--settings"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "displays": pane = .displays(nil)
            case "auto": pane = .auto
            case "keyboard": pane = .keyboard
            case "about": pane = .about
            default: break
            }
        }
    }
}

/// Dusk: indigo sky, a violet band and the last warm light near the horizon, with a soft moon glow.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.18, blue: 0.45), Color(red: 0.42, green: 0.30, blue: 0.62),
                    Color(red: 0.93, green: 0.55, blue: 0.48), Color(red: 0.99, green: 0.80, blue: 0.60),
                ], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Color.white.opacity(0.55), .clear], center: UnitPoint(x: 0.78, y: 0.16), startRadius: 4,
                endRadius: 220)
            RadialGradient(
                colors: [Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.35), .clear],
                center: UnitPoint(x: 0.1, y: 0.62), startRadius: 10, endRadius: 300)
        }
    }
}

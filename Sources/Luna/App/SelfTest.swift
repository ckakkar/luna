import AppKit
import LunaCore

/// `Luna --self-test`: drives the real app against the real displays and checks each result, then puts
/// everything back and quits with the number of failures as the exit status. It changes brightness for a
/// moment, so the screen flickers while it runs.
final class SelfTest {
    private let model: AppModel
    private let panel: PanelController
    private let keys: KeyController
    private let settingsWindow: SettingsWindowController
    private var failures = 0

    init(model: AppModel, panel: PanelController, keys: KeyController, settingsWindow: SettingsWindowController) {
        self.model = model
        self.panel = panel
        self.keys = keys
        self.settingsWindow = settingsWindow
    }

    private var controller: DisplayController { model.controller }

    func run() async {
        log("Luna \(AppInfo.version) self-test")
        // Let displays be found and probed over DDC.
        try? await Task.sleep(for: .seconds(4))
        check(!controller.displays.isEmpty, "found \(controller.displays.count) display(s)")

        for display in controller.displays {
            log(
                "• \(display.name): \(display.kind.rawValue), \(display.control.label), contrast \(display.offersContrast), "
                    + "volume \(display.offersVolume), input \(display.offersInput), XDR \(display.isXDRCapable) "
                    + "(headroom \(String(format: "%.1f", display.edrHeadroom))), DDC answers \(display.ddcResponsive)")
            await testBrightness(display)
            await testDimming(display)
            if display.isXDRCapable { await testXDR(display) }
        }
        await testCorners()
        await testWindows()

        let snapshot = controller.displays.map { ($0.id, gammaPeak($0.id)) }
        controller.stop()
        try? await Task.sleep(for: .milliseconds(300))
        for (id, peak) in snapshot where peak != nil {
            check((gammaPeak(id) ?? 0) > 0.99, "display \(id): colour table back to normal after quitting")
        }
        check(controller.cornerWindowCount == 0, "no corner windows left after quitting")
        log(failures == 0 ? "PASS" : "FAIL: \(failures) check(s) failed")
        exit(Int32(failures))
    }

    private func testBrightness(_ display: Display) async {
        let original = display.level
        let target = Level(
            brightness: original.brightness > 0.5 ? original.brightness - 0.2 : original.brightness + 0.2)
        display.setLevel(target, byUser: false)
        try? await Task.sleep(for: .milliseconds(600))
        switch display.control {
        case .apple:
            let actual = AppleNative.brightness(display.id) ?? -1
            check(
                abs(actual - target.brightness) < 0.03, "\(display.name): brightness set through macOS (\(fmt(actual)))"
            )
            // Changes from outside Luna (keys, Control Center) reach the slider.
            AppleNative.setBrightness(original.brightness, for: display.id)
            try? await Task.sleep(for: .milliseconds(1200))
            check(
                abs(display.level.brightness - original.brightness) < 0.03,
                "\(display.name): slider followed an outside change (\(fmt(display.level.brightness)))")
        case .software:
            let peak = gammaPeak(display.id) ?? 1
            let expected = SoftwareDimming.factor(target, hardware: false)
            check(abs(peak - expected) < 0.03, "\(display.name): dimmed in software to \(fmt(peak))")
        case .ddc:
            log("  \(display.name): brightness sent over DDC (check the monitor changed)")
        case .preview:
            break
        }
        display.setLevel(original, byUser: false)
        try? await Task.sleep(for: .milliseconds(400))
    }

    private func testDimming(_ display: Display) async {
        guard model.settings.allowDimming, display.dimMethod == .gamma, gammaPeak(display.id) != nil else { return }
        let original = display.level
        display.setLevel(Level(dim: 0.5, brightness: 0), byUser: false)
        try? await Task.sleep(for: .milliseconds(500))
        let expected = SoftwareDimming.factor(display.level, hardware: display.control != .software)
        let peak = gammaPeak(display.id) ?? 1
        check(abs(peak - expected) < 0.03, "\(display.name): below 0% dims the colour table to \(fmt(peak))")
        display.setLevel(original, byUser: false)
        try? await Task.sleep(for: .milliseconds(500))
        check((gammaPeak(display.id) ?? 0) > 0.99 || original.dim > 0, "\(display.name): colour table restored")
    }

    private func testXDR(_ display: Display) async {
        let wasOn = display.xdr
        let original = display.level
        display.setXDR(true)
        try? await Task.sleep(for: .milliseconds(1500))
        check(display.isBoosting, "\(display.name): XDR overlay up")
        let current = NSScreen.with(displayID: display.id)?.maximumExtendedDynamicRangeColorComponentValue ?? 1
        check(current > 1.01, "\(display.name): macOS opened the HDR headroom (\(fmt(Double(current))))")
        display.setXDR(false)
        try? await Task.sleep(for: .milliseconds(500))
        check(!display.isBoosting, "\(display.name): XDR overlay gone")
        if wasOn { display.setXDR(true) }
        display.setLevel(original, byUser: false)
    }

    private func testCorners() async {
        let wasOn = model.settings.roundedCorners
        model.setRoundedCorners(true)
        try? await Task.sleep(for: .milliseconds(300))
        check(
            controller.cornerWindowCount == 4 * NSScreen.screens.count,
            "rounded corners: \(controller.cornerWindowCount) windows")
        model.setRoundedCorners(false)
        check(controller.cornerWindowCount == 0, "rounded corners off")
        model.setRoundedCorners(wasOn)
    }

    private func testWindows() async {
        panel.show()
        try? await Task.sleep(for: .milliseconds(600))
        check(panel.isShown, "panel opens under the menu bar icon")
        panel.hide()
        if let display = controller.displays.first {
            keys.showBrightnessHUD(display)
            try? await Task.sleep(for: .milliseconds(300))
            check(NSApp.windows.contains { $0.isVisible && $0.frame.width == 252 }, "brightness indicator shows")
        }
        settingsWindow.show(.displays(nil))
        try? await Task.sleep(for: .milliseconds(800))
        check(NSApp.windows.contains { $0.isVisible && $0.title == "Luna Settings" }, "Settings opens")
        NSApp.windows.first { $0.title == "Luna Settings" }?.close()
        check(
            model.updater.isAvailable == (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != ""),
            "updater \(model.updater.isAvailable ? "on" : "off (local build)")")
    }

    private func gammaPeak(_ display: CGDirectDisplayID) -> Double? {
        var red = [CGGammaValue](repeating: 0, count: 256)
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, 256, &red, &green, &blue, &count) == .success, count > 0 else {
            return nil
        }
        return Double(red.prefix(Int(count)).max() ?? 0)
    }

    private func check(_ ok: Bool, _ message: String) {
        if !ok { failures += 1 }
        log("\(ok ? "✓" : "✗") \(message)")
    }

    private func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
}

import AppKit
import LunaCore
import Observation
import SwiftUI

@Observable
final class SettingsRouter {
    var pane: String? = "general"
    var displayID: CGDirectDisplayID?
}

/// Luna's Settings, in an ordinary window with a sidebar like System Settings.
final class SettingsWindowController {
    private let model: AppModel
    private let router = SettingsRouter()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(_ pane: SettingsPane) {
        router.pane = pane.id
        if case let .displays(id) = pane, let id { router.displayID = id }

        let window = self.window ?? makeWindow()
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Luna Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 440)
        let hosting = NSHostingController(rootView: SettingsView(router: router).environment(model))
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 760, height: 580))
        self.window = window
        return window
    }
}

struct SettingsView: View {
    @Bindable var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            List(selection: $router.pane) {
                SidebarRow(title: "General", symbol: "gearshape.fill", color: .gray).tag("general")
                SidebarRow(title: "Displays", symbol: "display", color: .blue).tag("displays")
                SidebarRow(title: "Auto Brightness", symbol: "sun.horizon.fill", color: .orange).tag("auto")
                SidebarRow(title: "Keyboard", symbol: "keyboard.fill", color: .indigo).tag("keyboard")
                SidebarRow(title: "About", symbol: "moon.stars.fill", color: .purple).tag("about")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 240)
        } detail: {
            Group {
                switch router.pane {
                case "displays": DisplaysPane(router: router)
                case "auto": AutoBrightnessPane()
                case "keyboard": KeyboardPane()
                case "about": AboutPane()
                default: GeneralPane()
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SidebarRow: View {
    var title: String
    var symbol: String
    var color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var autoUpdates = false

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle("Open Luna at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
                    }
                if LaunchAtLogin.needsApproval {
                    HStack {
                        Text("Allow Luna under Login Items in System Settings.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LaunchAtLogin.openSystemSettings() }
                    }
                }
            }

            Section("Brightness") {
                Picker("Brightness keys change", selection: $settings.keysTarget) {
                    Text("The display with the pointer").tag(KeysTarget.pointer)
                    Text("All displays").tag(KeysTarget.all)
                    Text("The main display").tag(KeysTarget.main)
                }
                Toggle(isOn: $settings.allowDimming) {
                    Text("Dim below 0%")
                    Text("The slider and keys go darker than the display's lowest setting, for late nights.")
                }
                Toggle(isOn: $settings.keysEnterXDR) {
                    Text("Brightness up at 100% turns on XDR")
                    Text("On displays with HDR headroom, like a MacBook Pro or Pro Display XDR.")
                }
                Toggle(isOn: $settings.controlVolumeKeys) {
                    Text("Volume keys control monitor speakers")
                    Text("When sound plays through a monitor whose volume macOS can't change.")
                }
            }

            Section("Rounded corners") {
                Toggle(
                    "Round the corners of every screen",
                    isOn: Binding(
                        get: { settings.roundedCorners }, set: { model.setRoundedCorners($0) }))
                LabeledContent("Radius") {
                    HStack {
                        Slider(value: $settings.cornerRadius, in: 4...28, step: 1)
                            .frame(maxWidth: 220)
                            .onChange(of: settings.cornerRadius) { model.controller.updateCorners() }
                        Text("\(Int(settings.cornerRadius)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!settings.roundedCorners)
            }

            Section("Updates") {
                if model.updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: $autoUpdates)
                        .onChange(of: autoUpdates) { _, on in model.updater.automaticallyChecks = on }
                    HStack {
                        Text("Luna \(AppInfo.version)").foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { model.updater.checkForUpdates() }
                    }
                } else {
                    Text("This copy of Luna was built locally and doesn't update itself.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
            autoUpdates = model.updater.automaticallyChecks
        }
    }
}

// MARK: - Displays

struct DisplaysPane: View {
    @Environment(AppModel.self) private var model
    @Bindable var router: SettingsRouter

    var body: some View {
        let displays = model.controller.displays
        let selected = displays.first { $0.id == router.displayID } ?? displays.first
        VStack(spacing: 0) {
            if displays.count > 1 {
                Picker("Display", selection: Binding(get: { selected?.id }, set: { router.displayID = $0 })) {
                    ForEach(displays) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 20)
            }
            if let selected {
                DisplayForm(display: selected)
                    .id(selected.id)
            } else {
                ContentUnavailableView(
                    "No Displays", systemImage: "display", description: Text("Connect a display to set it up."))
            }
        }
    }
}

private struct DisplayForm: View {
    var display: Display
    @Environment(AppModel.self) private var model
    @ViewState private var testing = false
    @ViewState private var testResult: String?
    @ViewState private var advanced = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: display.kind == .builtin ? "laptopcomputer" : "display")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.blue.gradient)
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(display.name).font(.title3.weight(.semibold))
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                TextField(
                    "Name",
                    text: Binding(get: { display.settings.nickname ?? "" }, set: { display.settings.nickname = $0 }),
                    prompt: Text(display.systemName))
            }

            Section("Brightness") {
                LabeledContent("Lowest") {
                    slider(
                        Binding(
                            get: { display.settings.minBrightness },
                            set: { value in
                                display.updateSettings { $0.minBrightness = min(value, $0.maxBrightness - 0.05) }
                            }))
                }
                LabeledContent("Highest") {
                    slider(
                        Binding(
                            get: { display.settings.maxBrightness },
                            set: { value in
                                display.updateSettings { $0.maxBrightness = max(value, $0.minBrightness + 0.05) }
                            }))
                }
                if display.offersContrast, display.control == .ddc {
                    Toggle(
                        isOn: Binding(
                            get: { display.settings.linkContrast },
                            set: { on in
                                display.updateSettings { $0.linkContrast = on }
                            })
                    ) {
                        Text("Lower contrast with brightness")
                        Text("Lets the monitor go dimmer than its backlight alone.")
                    }
                }
                if display.offersContrast {
                    LabeledContent("Contrast") {
                        slider(Binding(get: { display.contrast }, set: { display.setContrast($0) }))
                    }
                }
            }

            if display.reportsNothing || display.settings.showAllControls {
                Section {
                    Toggle(
                        isOn: Binding(
                            get: { display.settings.showAllControls },
                            set: { on in
                                display.updateSettings { $0.showAllControls = on }
                            })
                    ) {
                        Text("Show contrast, volume and input")
                        Text(
                            "This monitor answers DDC but doesn't report its settings, so Luna can't tell which of these it has. Turn on to try them."
                        )
                    }
                }
            }

            if display.offersVolume {
                Section("Sound") {
                    Toggle(
                        "Show volume in the menu bar panel",
                        isOn: Binding(
                            get: { display.settings.showVolume }, set: { on in display.settings.showVolume = on }))
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Button(testing ? "Testing…" : "Test Controls") {
                        testing = true
                        Task {
                            testResult = await display.runTest()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    if let testResult {
                        Text(testResult).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } footer: {
                Text("Dips the brightness for a moment and checks what the display answers to.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    Picker(
                        "Control", selection: Binding(get: { display.settings.method }, set: { display.setMethod($0) })
                    ) {
                        Text("Automatic").tag(ControlMethod.automatic)
                        Text("Hardware (DDC)").tag(ControlMethod.hardware)
                        Text("Software dimming").tag(ControlMethod.software)
                    }
                    if display.kind == .external || display.kind == .apple {
                        Toggle(
                            isOn: Binding(
                                get: { display.settings.slowDDC },
                                set: { on in display.updateSettings { $0.slowDDC = on } })
                        ) {
                            Text("Slow monitor")
                            Text("Waits longer between messages. Try this if changes are skipped or flicker.")
                        }
                        Picker(
                            "Input switching",
                            selection: Binding(
                                get: { display.settings.inputMethod },
                                set: { method in
                                    display.updateSettings { $0.inputMethod = method }
                                })
                        ) {
                            Text("Standard").tag(InputMethod.standard)
                            Text("LG").tag(InputMethod.lg)
                        }
                    }
                    Picker(
                        "Dimming below 0%",
                        selection: Binding(
                            get: { display.settings.dimMethod },
                            set: { method in
                                display.updateSettings { $0.dimMethod = method }
                            })
                    ) {
                        Text("Automatic").tag(DimMethod.automatic)
                        Text("Colour table (gamma)").tag(DimMethod.gamma)
                        Text("Dark overlay").tag(DimMethod.overlay)
                    }
                    HStack {
                        Spacer()
                        Button("Reset This Display", role: .destructive) {
                            display.resetSettings()
                            testResult = nil
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var status: String {
        var parts = [display.control.label]
        if let input = display.input.flatMap(InputSource.name(for:)) { parts.append(input) }
        if display.isXDRCapable { parts.append("XDR") }
        return parts.joined(separator: " · ")
    }

    private func slider(_ value: Binding<Double>) -> some View {
        HStack {
            Slider(value: value, in: 0...1)
                .frame(maxWidth: 220)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Auto brightness

struct AutoBrightnessPane: View {
    @Environment(AppModel.self) private var model
    @ViewState private var forgot = false

    var body: some View {
        let settings = model.settings
        Form {
            Section {
                modeRow(
                    .off, title: "Off", symbol: "hand.raised.fill", color: .gray,
                    detail: "Brightness stays where you put it.")
                modeRow(
                    .sync, title: "Match Mac", symbol: "laptopcomputer", color: .blue,
                    detail: model.controller.canSync
                        ? "Other displays follow the built-in display, which follows the light in the room."
                        : "Needs a built-in or Apple display alongside another display."
                )
                .disabled(!model.controller.canSync && settings.autoMode != .sync)
                modeRow(
                    .sun, title: "Sun", symbol: "sun.max.fill", color: .orange,
                    detail: "Brightness rises in the morning and falls in the evening, with the daylight where you are."
                )
            } header: {
                Text("Auto brightness")
            } footer: {
                Text(
                    "Move a slider while auto brightness is on and Luna remembers: next time, at that light, it goes where you put it."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }

            if settings.autoMode == .sun {
                Section("Today") {
                    DaylightGraph(location: settings.location ?? AutoBrightness.approximateLocation())
                        .frame(height: 120)
                        .padding(.vertical, 6)
                    HStack {
                        if let location = settings.location, !location.approximate {
                            Label("Using your location", systemImage: "location.fill").foregroundStyle(.secondary)
                        } else {
                            Label("Guessing your location from the time zone", systemImage: "location.slash")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Use My Location") { model.controller.auto.requestLocation() }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text("Forget my adjustments")
                    Spacer()
                    Button(forgot ? "Forgotten" : "Forget") {
                        model.controller.store.forgetLearnedCurves()
                        for display in model.controller.displays {
                            display.updateSettings {
                                $0.syncCurve = DisplaySettings().syncCurve
                                $0.sunCurve = DisplaySettings().sunCurve
                            }
                        }
                        forgot = true
                        model.controller.auto.update()
                    }
                    .disabled(forgot)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func modeRow(_ mode: AutoMode, title: String, symbol: String, color: Color, detail: String) -> some View {
        Button {
            model.setAutoMode(mode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.settings.autoMode == mode {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Daylight across today, with sunrise, sunset and now.
struct DaylightGraph: View {
    var location: SavedLocation

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let samples = (0...96).map { i -> Double in
            Solar.daylight(
                at: start.addingTimeInterval(Double(i) * 900), latitude: location.latitude,
                longitude: location.longitude)
        }
        let now = Date().timeIntervalSince(start) / 86400
        let (sunrise, sunset) = sunTimes(from: start)

        VStack(spacing: 6) {
            Canvas { context, size in
                var line = Path()
                for (i, value) in samples.enumerated() {
                    let point = CGPoint(x: size.width * Double(i) / 96, y: size.height * (1 - value * 0.9) - 2)
                    i == 0 ? line.move(to: point) : line.addLine(to: point)
                }
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [.orange.opacity(0.45), .indigo.opacity(0.08)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(line, with: .color(.orange), lineWidth: 2)

                let x = size.width * now
                let value = Solar.daylight(at: Date(), latitude: location.latitude, longitude: location.longitude)
                let dot = CGPoint(x: x, y: size.height * (1 - value * 0.9) - 2)
                context.stroke(
                    Path {
                        $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(.orange))
                context.stroke(
                    Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(.white),
                    lineWidth: 2)
            }
            HStack {
                if let sunrise {
                    Label(sunrise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
                }
                Spacer()
                Text("Now").foregroundStyle(.secondary)
                Spacer()
                if let sunset { Label(sunset.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func sunTimes(from start: Date) -> (Date?, Date?) {
        var sunrise: Date?
        var sunset: Date?
        var previous = Solar.elevation(at: start, latitude: location.latitude, longitude: location.longitude)
        for minute in stride(from: 5, through: 1440, by: 5) {
            let date = start.addingTimeInterval(Double(minute) * 60)
            let elevation = Solar.elevation(at: date, latitude: location.latitude, longitude: location.longitude)
            if previous < -0.83, elevation >= -0.83, sunrise == nil { sunrise = date }
            if previous >= -0.83, elevation < -0.83 { sunset = date }
            previous = elevation
        }
        return (sunrise, sunset)
    }
}

// MARK: - Keyboard

struct KeyboardPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: model.keysEnabled ? "checkmark.seal.fill" : "lock.fill")
                        .font(.title2)
                        .foregroundStyle(
                            model.keysEnabled ? AnyShapeStyle(.green.gradient) : AnyShapeStyle(.orange.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            model.keysEnabled
                                ? "Brightness and volume keys work on every display" : "Brightness and volume keys"
                        )
                        .font(.body.weight(.medium))
                        Text(
                            model.keysEnabled
                                ? "Hold ⌥⇧ while pressing a key for smaller steps."
                                : "Luna needs Accessibility permission to see these keys. It doesn't read anything you type."
                        )
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !model.keysEnabled {
                        Button("Enable…") { model.enableKeys() }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(title(action)) {
                        ShortcutRecorder(combo: model.settings.shortcuts[action]) { combo in
                            model.settings.shortcuts[action] = combo
                            HotKeys.shared.register(model.settings.shortcuts)
                        }
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Work in any app. Brightness shortcuts change the display with the pointer.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func title(_ action: ShortcutAction) -> String {
        switch action {
        case .brightnessUp: "Brighter"
        case .brightnessDown: "Dimmer"
        case .toggleXDR: "Turn XDR on or off"
        case .toggleCorners: "Rounded corners on or off"
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: AppInfo.icon)
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            VStack(spacing: 4) {
                Text("Luna").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            }
            Text("Brightness, volume, XDR and rounded corners for every display.\nFree and open source.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Link("GitHub", destination: AppInfo.repository)
                Text("·").foregroundStyle(.tertiary)
                Link("Guide", destination: AppInfo.usage)
                Text("·").foregroundStyle(.tertiary)
                Link("Report an Issue", destination: AppInfo.issues)
                Text("·").foregroundStyle(.tertiary)
                Link("Credits", destination: AppInfo.credits)
            }
            .padding(.top, 4)
            Spacer()
            Text("MIT License · app by cyrus")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }
}

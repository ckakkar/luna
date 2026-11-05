import AppKit
import LunaCore
import Observation
import SwiftUI

@Observable
final class SettingsRouter {
    var pane: String = "general"
    var displayID: CGDirectDisplayID?
}

/// Luna's Settings: a floating glass sidebar over a soft aurora, and panes of frosted cards.
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Luna Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 520)
        let hosting = NSHostingController(rootView: SettingsView(router: router).environment(model))
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 820, height: 600))
        self.window = window
        return window
    }
}

struct SettingsView: View {
    @Bindable var router: SettingsRouter

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $router.pane)
                .frame(width: 214)
                .padding(10)
            ScrollView {
                Group {
                    switch router.pane {
                    case "displays": DisplaysPane(router: router)
                    case "auto": AutoBrightnessPane()
                    case "keyboard": KeyboardPane()
                    case "about": AboutPane()
                    default: GeneralPane()
                    }
                }
                .paneWidth()
                .padding(.horizontal, 28)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .id(router.pane)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .scrollBounceBehavior(.basedOnSize)
            .animation(.luna, value: router.pane)
        }
        .background(AuroraBackground())
        .focusEffectDisabled()
    }
}

/// The panes, as a floating glass column with a highlight that slides to the selection.
private struct Sidebar: View {
    @Binding var selection: String
    @Namespace private var highlight
    @ViewState private var hovering: String?

    private let items: [(id: String, title: String, symbol: String, color: Color)] = [
        ("general", "General", "gearshape.fill", .gray),
        ("displays", "Displays", "display", .blue),
        ("auto", "Auto Brightness", "sun.horizon.fill", .orange),
        ("keyboard", "Keyboard", "keyboard.fill", .indigo),
        ("about", "About", "moon.stars.fill", .purple),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LunaMark(size: 20)
                Text("Luna").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.top, 40)  // below the window's buttons
            .padding(.bottom, 14)

            ForEach(items, id: \.id) { item in
                Button {
                    withAnimation(.luna) { selection = item.id }
                } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: item.symbol, color: item.color, size: 26)
                        Text(item.title).font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 38)
                    .background {
                        if selection == item.id {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(0.10))
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        } else if hovering == item.id {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { inside in hovering = inside ? item.id : (hovering == item.id ? nil : hovering) }
                .accessibilityAddTraits(selection == item.id ? .isSelected : [])
            }

            Spacer()

            Text("Version \(AppInfo.version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var autoUpdates = false

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(
                symbol: "gearshape.fill", color: .gray, title: "General",
                subtitle: "How Luna starts, and what your keys and screen corners do.")

            SettingsCard(title: "Startup") {
                SettingRow(
                    symbol: "power", color: .green, title: "Open at login",
                    detail: LaunchAtLogin.needsApproval
                        ? "Waiting for you to allow Luna in System Settings › Login Items." : nil
                ) {
                    if LaunchAtLogin.needsApproval {
                        Button("Open Login Items") { LaunchAtLogin.openSystemSettings() }
                            .buttonStyle(ChipButtonStyle())
                    }
                    CapsuleSwitch(label: "Open at login", isOn: $launchAtLogin)
                }
            }
            .onChange(of: launchAtLogin) { _, on in
                LaunchAtLogin.set(on)
                launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
            }

            SettingsCard(title: "Brightness") {
                SettingRow(symbol: "keyboard", color: .indigo, title: "Brightness keys change") {
                    SegmentedPill(
                        options: [
                            .init(value: KeysTarget.pointer, title: "Pointer", symbol: "cursorarrow"),
                            .init(value: KeysTarget.all, title: "All"),
                            .init(value: KeysTarget.main, title: "Main"),
                        ],
                        selection: settings.keysTarget, onSelect: { settings.keysTarget = $0 })
                }
                RowDivider()
                SettingRow(
                    symbol: "moon.fill", color: Color(red: 0.36, green: 0.40, blue: 0.86), title: "Dim below 0%",
                    detail: "Darker than the display's lowest setting, for late nights."
                ) {
                    CapsuleSwitch(label: "Dim below 0%", isOn: $settings.allowDimming)
                }
                RowDivider()
                SettingRow(
                    symbol: "sparkles", color: .orange, title: "Brightness up at 100% turns on XDR",
                    detail: "On Apple's XDR displays, like a MacBook Pro or Pro Display XDR."
                ) {
                    CapsuleSwitch(label: "XDR from the keys", isOn: $settings.keysEnterXDR)
                }
                RowDivider()
                SettingRow(
                    symbol: "speaker.wave.2.fill", color: .pink, title: "Volume keys control monitor speakers",
                    detail: "When sound plays through a monitor whose volume macOS can't change."
                ) {
                    CapsuleSwitch(label: "Volume keys", isOn: $settings.controlVolumeKeys)
                }
            }
            .onChange(of: settings.allowDimming) { model.controller.dimmingSettingChanged() }

            SettingsCard(title: "Rounded corners") {
                SettingRow(symbol: "viewfinder", color: .teal, title: "Round the corners of every screen") {
                    CapsuleSwitch(
                        label: "Rounded corners",
                        isOn: Binding(get: { settings.roundedCorners }, set: { model.setRoundedCorners($0) }))
                }
                RowDivider()
                HStack(spacing: 14) {
                    CornerPreview(radius: settings.roundedCorners ? settings.cornerRadius : 0)
                    GlassSlider(
                        value: (settings.cornerRadius - 4) / 24, icon: "viewfinder",
                        label: "\(Int(settings.cornerRadius)) pt", height: 26, accessibilityName: "Corner radius"
                    ) { position in
                        settings.cornerRadius = (4 + position * 24).rounded()
                        model.controller.updateCorners()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .opacity(settings.roundedCorners ? 1 : 0.45)
                .disabled(!settings.roundedCorners)
            }

            SettingsCard(title: "Updates") {
                if model.updater.isAvailable {
                    SettingRow(
                        symbol: "arrow.triangle.2.circlepath", color: .blue, title: "Check for updates automatically",
                        detail: "Every hour. You'll see what changed before anything installs."
                    ) {
                        CapsuleSwitch(label: "Automatic updates", isOn: $autoUpdates)
                    }
                    RowDivider()
                    SettingRow(symbol: "shippingbox.fill", color: .purple, title: "Luna \(AppInfo.version)") {
                        Button("Check Now") { model.updater.checkForUpdates() }
                            .buttonStyle(ChipButtonStyle())
                    }
                } else {
                    SettingRow(
                        symbol: "hammer.fill", color: .gray, title: "Built locally",
                        detail: "This copy of Luna doesn't update itself."
                    ) { EmptyView() }
                }
            }
            .onChange(of: autoUpdates) { _, on in model.updater.automaticallyChecks = on }
        }
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
            autoUpdates = model.updater.automaticallyChecks
        }
    }
}

/// A screen's top corner, drawn at the chosen radius: the black around it is what the mask covers.
private struct CornerPreview: View {
    var radius: Double

    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.36, green: 0.40, blue: 0.86), Color(red: 0.95, green: 0.62, blue: 0.48)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius * 0.9, style: .continuous))
        .frame(width: 44, height: 30)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 3))
        .animation(.luna, value: radius)
        .accessibilityHidden(true)
    }
}

// MARK: - Displays

struct DisplaysPane: View {
    @Environment(AppModel.self) private var model
    @Bindable var router: SettingsRouter

    var body: some View {
        let displays = model.controller.displays
        let selected = displays.first { $0.id == router.displayID } ?? displays.first
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(
                symbol: "display", color: .blue, title: "Displays",
                subtitle: "Names, brightness range, and how Luna talks to each display.")

            if displays.count > 1 {
                HStack(spacing: 10) {
                    ForEach(displays) { display in
                        DisplayTile(display: display, selected: display.id == selected?.id) {
                            withAnimation(.luna) { router.displayID = display.id }
                        }
                    }
                }
            }

            if let selected {
                DisplayForm(display: selected)
                    .id(selected.id)
            } else {
                SettingsCard {
                    VStack(spacing: 10) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No displays").font(.headline)
                        Text("Connect a display to set it up.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                }
            }
        }
    }
}

/// A display to choose, when there's more than one.
private struct DisplayTile: View {
    var display: Display
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: display.kind == .builtin ? "laptopcomputer" : "display")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.secondary))
                Text(display.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct DisplayForm: View {
    var display: Display
    @Environment(AppModel.self) private var model
    @ViewState private var testing = false
    @ViewState private var testResult: String?
    @ViewState private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero

            SettingsCard(title: "Brightness") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Brightness range").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(
                            "\(Int((display.settings.minBrightness * 100).rounded()))–\(Int((display.settings.maxBrightness * 100).rounded()))%"
                        )
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    RangeCapsule(lower: display.settings.minBrightness, upper: display.settings.maxBrightness) {
                        lower, upper in
                        display.updateSettings {
                            $0.minBrightness = lower
                            $0.maxBrightness = upper
                        }
                    }
                    Text("The share of the monitor's own range that Luna's 0–100% covers.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                if display.offersContrast {
                    RowDivider(inset: 14)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Contrast").font(.system(size: 13, weight: .medium))
                        GlassSlider(
                            value: display.contrast, icon: "circle.lefthalf.filled",
                            label: "\(Int((display.contrast * 100).rounded()))", height: 26,
                            accessibilityName: "\(display.name) contrast"
                        ) { display.setContrast($0) }
                    }
                    .padding(14)
                }
                if display.offersContrast, display.control == .ddc {
                    RowDivider()
                    SettingRow(
                        symbol: "circle.lefthalf.filled", color: .gray, title: "Lower contrast with brightness",
                        detail: "Lets the monitor go dimmer than its backlight alone."
                    ) {
                        CapsuleSwitch(
                            label: "Link contrast",
                            isOn: Binding(
                                get: { display.settings.linkContrast },
                                set: { on in display.updateSettings { $0.linkContrast = on } }))
                    }
                }
            }

            if display.reportsNothing || display.settings.showAllControls || display.offersVolume {
                SettingsCard(title: "Controls") {
                    if display.reportsNothing || display.settings.showAllControls {
                        SettingRow(
                            symbol: "slider.horizontal.3", color: .teal, title: "Show contrast, volume and input",
                            detail:
                                "This monitor answers DDC but doesn't report its settings, so Luna can't tell which of these it has. Turn on to try them."
                        ) {
                            CapsuleSwitch(
                                label: "Show all controls",
                                isOn: Binding(
                                    get: { display.settings.showAllControls },
                                    set: { on in display.updateSettings { $0.showAllControls = on } }))
                        }
                        if display.offersVolume { RowDivider() }
                    }
                    if display.offersVolume {
                        SettingRow(symbol: "speaker.wave.2.fill", color: .pink, title: "Show volume in the panel") {
                            CapsuleSwitch(
                                label: "Show volume",
                                isOn: Binding(
                                    get: { display.settings.showVolume },
                                    set: { on in display.settings.showVolume = on }))
                        }
                    }
                }
            }

            SettingsCard(footer: "Dips the brightness for a moment and checks what the display answers to.") {
                SettingRow(
                    symbol: "checkmark.seal.fill", color: .green, title: "Test controls",
                    detail: testResult
                ) {
                    Button(testing ? "Testing…" : "Test") {
                        testing = true
                        Task {
                            testResult = await display.runTest()
                            testing = false
                        }
                    }
                    .buttonStyle(ChipButtonStyle(prominent: true))
                    .disabled(testing)
                }
            }

            SettingsCard {
                Disclosure(title: "Advanced", symbol: "wrench.and.screwdriver.fill", isExpanded: $advanced) {
                    advancedRows
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 18) {
            MonitorArt(display: display)
            VStack(alignment: .leading, spacing: 8) {
                // Shows the display's name in full; typing makes it a nickname, clearing it goes back to the
                // system's name.
                TextField(
                    "Name",
                    text: Binding(
                        get: { display.name },
                        set: { value in
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            display.settings.nickname = trimmed.isEmpty || trimmed == display.systemName ? nil : value
                        }),
                    prompt: Text(display.systemName)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    StatusChip(text: display.control.label, symbol: controlSymbol, tint: .blue)
                    if let input = display.input.flatMap(InputSource.name(for:)) {
                        StatusChip(text: input, symbol: "arrow.left.arrow.right")
                    }
                    if display.isXDRCapable { StatusChip(text: "XDR", symbol: "sparkles", tint: .orange) }
                }
                Text("Click the name to rename it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var controlSymbol: String {
        switch display.control {
        case .apple: "apple.logo"
        case .ddc: "cable.connector"
        case .software: "circle.lefthalf.filled"
        case .preview: "eye"
        }
    }

    // MARK: Advanced

    @ViewBuilder
    private var advancedRows: some View {
        SettingRow(symbol: "dial.medium.fill", color: .blue, title: "Brightness control") {
            SegmentedPill(
                options: [
                    .init(value: ControlMethod.automatic, title: "Auto"),
                    .init(value: ControlMethod.hardware, title: "DDC"),
                    .init(value: ControlMethod.software, title: "Software"),
                ],
                selection: display.settings.method, onSelect: { display.setMethod($0) })
        }
        if display.kind == .external || display.kind == .apple {
            RowDivider()
            SettingRow(
                symbol: "tortoise.fill", color: .green, title: "Slow monitor",
                detail: "Waits longer between messages. Try this if changes are skipped or flicker."
            ) {
                CapsuleSwitch(
                    label: "Slow monitor",
                    isOn: Binding(
                        get: { display.settings.slowDDC }, set: { on in display.updateSettings { $0.slowDDC = on } }))
            }
            RowDivider()
            SettingRow(symbol: "arrow.left.arrow.right", color: .purple, title: "Input switching") {
                SegmentedPill(
                    options: [
                        .init(value: InputMethod.standard, title: "Standard"),
                        .init(value: InputMethod.lg, title: "LG"),
                    ],
                    selection: display.settings.inputMethod,
                    onSelect: { method in display.updateSettings { $0.inputMethod = method } })
            }
        }
        if display.offersXDROnHDRMonitor {
            RowDivider()
            SettingRow(
                symbol: "sparkles", color: .orange, title: "Offer XDR on this HDR monitor",
                detail:
                    "Rarely brighter: macOS dims everything else to make room, so the screen can dip during Space swipes and in videos."
            ) {
                CapsuleSwitch(
                    label: "Offer XDR",
                    isOn: Binding(
                        get: { display.settings.allowXDR },
                        set: { on in
                            if !on { display.setXDR(false) }
                            display.updateSettings { $0.allowXDR = on }
                        }))
            }
        }
        RowDivider()
        SettingRow(symbol: "moon.fill", color: Color(red: 0.36, green: 0.40, blue: 0.86), title: "Dimming below 0%") {
            SegmentedPill(
                options: [
                    .init(value: DimMethod.automatic, title: "Auto"),
                    .init(value: DimMethod.gamma, title: "Colour"),
                    .init(value: DimMethod.overlay, title: "Overlay"),
                ],
                selection: display.settings.dimMethod,
                onSelect: { method in display.updateSettings { $0.dimMethod = method } })
        }
        RowDivider()
        SettingRow(
            symbol: "arrow.counterclockwise", color: .red, title: "Reset this display",
            detail: "Back to Luna's defaults; the current brightness stays."
        ) {
            Button("Reset", role: .destructive) {
                display.resetSettings()
                testResult = nil
            }
            .buttonStyle(ChipButtonStyle())
        }
    }
}

/// A small monitor whose screen glows with the display's brightness (gold in XDR, moonlight below 0%).
private struct MonitorArt: View {
    var display: Display

    var body: some View {
        let level = display.level
        let glow =
            level.dim > 0 ? 0.15 * (1 - level.dim) : level.boost > 0 ? 1 : 0.18 + 0.82 * level.brightness
        let screen = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(spacing: 0) {
            ZStack {
                screen.fill(Color.black.opacity(0.85))
                screen
                    .fill(
                        LinearGradient(
                            colors: level.boost > 0
                                ? [.white, Color(red: 1, green: 0.82, blue: 0.5)]
                                : [Color(red: 0.62, green: 0.66, blue: 1.0), Color(red: 1.0, green: 0.72, blue: 0.58)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .opacity(glow)
                    .padding(4)
                    .shadow(color: level.boost > 0 ? Palette.glow.opacity(0.7) : .clear, radius: 10)
            }
            .frame(width: 96, height: 60)
            if display.kind != .builtin {
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 14, height: 9)
                Capsule().fill(Color.primary.opacity(0.35)).frame(width: 40, height: 4)
            } else {
                Capsule().fill(Color.primary.opacity(0.35)).frame(width: 112, height: 5)
            }
        }
        .animation(.luna, value: glow)
        .accessibilityHidden(true)
    }
}

// MARK: - Auto brightness

struct AutoBrightnessPane: View {
    @Environment(AppModel.self) private var model
    @ViewState private var forgot = false

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(
                symbol: "sun.horizon.fill", color: .orange, title: "Auto Brightness",
                subtitle: "Let brightness follow the light, and learn where you like it.")

            HStack(spacing: 12) {
                ModeTile(
                    mode: .off, title: "Off", symbol: "hand.raised.fill", color: .gray,
                    detail: "Brightness stays where you put it.")
                ModeTile(
                    mode: .sync, title: "Match Mac", symbol: "laptopcomputer", color: .blue,
                    detail: model.controller.canSync
                        ? "Follows your Mac's display, which follows the room."
                        : "Needs a built-in or Apple display and one more.",
                    enabled: model.controller.canSync || settings.autoMode == .sync)
                ModeTile(
                    mode: .sun, title: "Sun", symbol: "sun.max.fill", color: .orange,
                    detail: "Rises in the morning, falls in the evening.")
            }

            if settings.autoMode == .sun {
                SettingsCard(title: "Today") {
                    DaylightGraph(location: settings.location ?? AutoBrightness.approximateLocation())
                        .frame(height: 150)
                        .padding(14)
                    RowDivider(inset: 14)
                    if let location = settings.location, !location.approximate {
                        SettingRow(
                            symbol: "location.fill", color: .blue, title: "Using your location",
                            detail: "Only on this Mac, to know when the sun rises and sets."
                        ) { EmptyView() }
                    } else {
                        SettingRow(
                            symbol: "location.slash.fill", color: .gray, title: "Guessing from your time zone",
                            detail: "Good to within an hour or so of real sunrise and sunset."
                        ) {
                            Button("Use My Location") { model.controller.auto.requestLocation() }
                                .buttonStyle(ChipButtonStyle(prominent: true))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingsCard(
                footer:
                    "Move a slider while auto brightness is on and Luna remembers: next time, at that light, it goes where you put it."
            ) {
                SettingRow(symbol: "brain.head.profile", color: .pink, title: "Forget my adjustments") {
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
                    .buttonStyle(ChipButtonStyle())
                    .disabled(forgot)
                }
            }
        }
        .animation(.luna, value: settings.autoMode)
    }
}

/// One auto-brightness mode, as a large tile that lights up when chosen.
private struct ModeTile: View {
    var mode: AutoMode
    var title: String
    var symbol: String
    var color: Color
    var detail: String
    var enabled = true

    @Environment(AppModel.self) private var model
    @ViewState private var hovering = false

    var body: some View {
        let selected = model.settings.autoMode == mode
        Button {
            withAnimation(.luna) { model.setAutoMode(mode) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: symbol, color: color, size: 34)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.16 : 0.08),
                        lineWidth: selected ? 2 : 0.5)
            )
            .shadow(color: selected ? Color.accentColor.opacity(0.25) : .clear, radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Today's daylight as a sky: night at the edges, the sun's arc through the day, and where it is now.
struct DaylightGraph: View {
    var location: SavedLocation

    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let samples = (0...96).map { i -> Double in
            Solar.daylight(
                at: start.addingTimeInterval(Double(i) * 900), latitude: location.latitude,
                longitude: location.longitude)
        }
        let now = Date().timeIntervalSince(start) / 86400
        let (sunrise, sunset) = sunTimes(from: start)

        VStack(spacing: 8) {
            Canvas { context, size in
                let sky = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12, style: .continuous)
                context.clip(to: sky)
                // Night to day across the hours, following the daylight.
                let stops = samples.enumerated().map { i, value in
                    Gradient.Stop(
                        color: Color(
                            red: 0.10 + 0.25 * value, green: 0.12 + 0.42 * value, blue: 0.32 + 0.45 * value),
                        location: Double(i) / 96)
                }
                context.fill(
                    sky,
                    with: .linearGradient(
                        Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))

                func point(_ i: Int, _ value: Double) -> CGPoint {
                    CGPoint(x: size.width * Double(i) / 96, y: size.height * (1 - value * 0.78) - 10)
                }
                var arc = Path()
                for (i, value) in samples.enumerated() {
                    i == 0 ? arc.move(to: point(i, value)) : arc.addLine(to: point(i, value))
                }
                var area = arc
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 1, green: 0.78, blue: 0.42).opacity(0.55), .clear]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(arc, with: .color(Color(red: 1, green: 0.82, blue: 0.5)), lineWidth: 2.5)

                let value = Solar.daylight(at: Date(), latitude: location.latitude, longitude: location.longitude)
                let sun = CGPoint(x: size.width * now, y: size.height * (1 - value * 0.78) - 10)
                context.stroke(
                    Path {
                        $0.move(to: CGPoint(x: sun.x, y: 0))
                        $0.addLine(to: CGPoint(x: sun.x, y: size.height))
                    }, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                for (radius, alpha) in [(18.0, 0.18), (11.0, 0.35)] {
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(alpha)))
                }
                context.fill(
                    Path(ellipseIn: CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12)), with: .color(.white))
            }
            HStack {
                if let sunrise {
                    Label(sunrise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
                }
                Spacer()
                Text("Now \(Date().formatted(date: .omitted, time: .shortened))")
                Spacer()
                if let sunset { Label(sunset.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill") }
            }
            .font(.system(size: 11, weight: .medium))
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
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(
                symbol: "keyboard.fill", color: .indigo, title: "Keyboard",
                subtitle: "Your keyboard's brightness and volume keys, and shortcuts of your own.")

            SettingsCard {
                HStack(spacing: 14) {
                    IconTile(
                        symbol: model.keysEnabled ? "checkmark.seal.fill" : "lock.fill",
                        color: model.keysEnabled ? .green : .orange, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.keysEnabled ? "Working on every display" : "Brightness and volume keys")
                            .font(.system(size: 14, weight: .semibold))
                        Text(
                            model.keysEnabled
                                ? "Hold ⌥⇧ while pressing a key for smaller steps."
                                : "Luna needs Accessibility permission to see these keys. It never sees what you type."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !model.keysEnabled {
                        Button("Enable") { model.enableKeys() }
                            .buttonStyle(ChipButtonStyle(prominent: true))
                    }
                }
                .padding(16)
            }

            SettingsCard(
                title: "Shortcuts",
                footer: "They work in any app. Brightness shortcuts change the display with the pointer."
            ) {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { RowDivider() }
                    SettingRow(symbol: symbol(action), color: color(action), title: title(action)) {
                        ShortcutRecorder(combo: model.settings.shortcuts[action]) { combo in
                            model.settings.shortcuts[action] = combo
                            HotKeys.shared.register(model.settings.shortcuts)
                        }
                    }
                }
            }
        }
    }

    private func title(_ action: ShortcutAction) -> String {
        switch action {
        case .brightnessUp: "Brighter"
        case .brightnessDown: "Dimmer"
        case .toggleXDR: "XDR on or off"
        case .toggleCorners: "Rounded corners on or off"
        }
    }

    private func symbol(_ action: ShortcutAction) -> String {
        switch action {
        case .brightnessUp: "sun.max.fill"
        case .brightnessDown: "sun.min.fill"
        case .toggleXDR: "sparkles"
        case .toggleCorners: "viewfinder"
        }
    }

    private func color(_ action: ShortcutAction) -> Color {
        switch action {
        case .brightnessUp: .orange
        case .brightnessDown: Color(red: 0.36, green: 0.40, blue: 0.86)
        case .toggleXDR: .yellow
        case .toggleCorners: .teal
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.55, green: 0.5, blue: 1).opacity(0.45), .clear], center: .center,
                            startRadius: 10, endRadius: 120)
                    )
                    .frame(width: 240, height: 240)
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            }
            .padding(.top, 6)
            .padding(.bottom, -40)

            VStack(spacing: 8) {
                Text("Luna").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Version \(AppInfo.version)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Text("Brightness, volume, XDR and rounded corners for every display.\nFree and open source.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                link("GitHub", "chevron.left.forwardslash.chevron.right", AppInfo.repository)
                link("Guide", "book.fill", AppInfo.usage)
                link("Report an Issue", "exclamationmark.bubble.fill", AppInfo.issues)
                link("Credits", "heart.fill", AppInfo.credits)
            }
            .padding(.top, 4)

            Text("MIT License · app by cyrus")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private func link(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(ChipButtonStyle())
    }
}

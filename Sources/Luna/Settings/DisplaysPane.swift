import AppKit
import LunaCore
import Observation
import SwiftUI

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
                        Text("No displays to control").font(.headline)
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
                    // Laptop and monitor symbols differ in height; a fixed box keeps the names in line.
                    .frame(height: 32)
                Text(display.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
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
        .accessibilityLabel(display.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

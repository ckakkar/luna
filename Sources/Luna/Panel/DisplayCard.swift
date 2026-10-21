import LunaCore
import SwiftUI

/// One display: its name, brightness, and only the extras it actually supports.
struct DisplayCard: View {
    @Environment(AppModel.self) private var model
    var display: Display

    @ViewState private var expanded = false
    @ViewState private var pendingInput: InputSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            brightness
            if display.showsVolume { volume }
            if showsChips { chips }
            if let pendingInput { confirmInput(pendingInput) }
            if expanded { more }
        }
        .padding(12)
        .platter()
        .onAppear { if model.previewExpanded { expanded = true } }
        .animation(.luna, value: expanded)
        .animation(.luna, value: pendingInput)
        .animation(.luna, value: display.xdr)
        .animation(.luna, value: display.showsVolume)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(display.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if display.probing {
                ProgressView().controlSize(.mini).padding(.leading, 2)
                    .help("Asking the monitor what it supports…")
            }
            Spacer()
            if model.controller.canTurnOff(display) {
                CircleIconButton(systemImage: "power", help: "Turn off \(display.name)", tint: .red) {
                    model.controller.turnOff(display)
                }
            }
            CircleIconButton(systemImage: "ellipsis", help: expanded ? "Fewer options" : "More options") {
                expanded.toggle()
            }
            .rotationEffect(.degrees(expanded ? 90 : 0))
        }
    }

    private var symbol: String {
        switch display.kind {
        case .builtin: "laptopcomputer"
        case .apple, .external: "display"
        case .virtual: "rectangle.on.rectangle"
        }
    }

    // MARK: Brightness

    private var brightness: some View {
        let zones = display.zones
        var markers: [Double] = []
        if zones.dimWidth > 0 { markers.append(zones.zeroPosition) }
        if zones.boostWidth > 0 { markers.append(zones.fullPosition) }
        let level = display.level
        let tone: GlassSlider.Tone = level.dim > 0 ? .dim : level.boost > 0 ? .boost : .normal
        let icon =
            level.dim > 0
            ? "moon.fill" : level.boost > 0 ? "sun.max.fill" : level.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill"
        return GlassSlider(
            value: display.position, icon: icon, label: brightnessLabel, tone: tone, markers: markers,
            accessibilityName: "\(display.name) brightness"
        ) { display.setPosition($0) }
    }

    private var brightnessLabel: String {
        let level = display.level
        if level.dim > 0 { return "−\(Int((level.dim * 100).rounded()))%" }
        if level.boost > 0 {
            let multiplier = 1 + level.boost * (min(display.edrHeadroom, 3.2) - 1)
            return "\(Int((multiplier * 100).rounded()))%"
        }
        return "\(Int((level.brightness * 100).rounded()))%"
    }

    // MARK: Volume

    private var volume: some View {
        GlassSlider(
            value: display.muted ? 0 : display.volume,
            icon: display.muted ? "speaker.slash.fill" : "speaker.wave.3.fill",
            iconValue: display.muted ? nil : display.volume,
            label: display.muted ? "Muted" : "\(Int((display.volume * 100).rounded()))",
            accessibilityName: "\(display.name) volume",
            onIconTap: { display.setMuted(!display.muted) }
        ) { display.setVolume($0) }
    }

    // MARK: SDR / XDR and input

    private var showsChips: Bool { display.isXDRCapable || display.offersInput }

    private var chips: some View {
        HStack(spacing: 8) {
            if display.isXDRCapable {
                SegmentedPill(
                    options: [
                        .init(value: false, title: "SDR"),
                        .init(value: true, title: "XDR", symbol: "sparkles", glow: true),
                    ],
                    selection: display.xdr, onSelect: { display.setXDR($0) }
                )
                .help("XDR lets this display go past 100%, using the extra brightness it keeps for HDR")
            }
            Spacer(minLength: 0)
            if display.offersInput {
                Button {
                    showInputs()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .bold))
                        Text(display.input.flatMap(InputSource.name(for:)) ?? "Input")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(ChipButtonStyle())
                .help("Switch the monitor's input")
            }
        }
    }

    private func showInputs() {
        let sources = InputSource.sources(for: display.settings.inputMethod)
        PopUpMenu.show(
            sources.map { source in
                .init(title: source.name, checked: display.input == source.code) {
                    // With only this display, switching away leaves the Mac without a screen: confirm first.
                    if model.controller.displays.count == 1, display.input != source.code {
                        pendingInput = source
                    } else {
                        display.selectInput(source)
                    }
                }
            })
    }

    private func confirmInput(_ source: InputSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch to \(source.name)?")
                .font(.system(size: 12, weight: .semibold))
            Text("This Mac's picture goes away until you switch back with the monitor's buttons.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { pendingInput = nil }
                    .buttonStyle(ChipButtonStyle())
                Button("Switch") {
                    display.selectInput(source)
                    pendingInput = nil
                }
                .buttonStyle(ChipButtonStyle(prominent: true))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }

    // MARK: More

    private var more: some View {
        VStack(alignment: .leading, spacing: 9) {
            if display.offersContrast {
                GlassSlider(
                    value: display.contrast, icon: "circle.lefthalf.filled",
                    label: "\(Int((display.contrast * 100).rounded()))", height: 26,
                    accessibilityName: "\(display.name) contrast"
                ) { display.setContrast($0) }
                .help(
                    display.settings.linkContrast
                        ? "Contrast also follows brightness (change this in Settings)" : "Contrast")
            }
            HStack {
                Text(display.control.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Display Settings…") { model.openSettings(.displays(display.id)) }
                    .buttonStyle(ChipButtonStyle())
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

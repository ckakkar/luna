import AppKit
import LunaCore
import SwiftUI

/// The menu bar panel: a card per display, then auto brightness and rounded corners.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var appeared = true
    @ViewState private var contentHeight: CGFloat = 0

    private var controller: DisplayController { model.controller }
    private var settings: AppSettings { model.settings }

    /// Room the header takes above the scrolling part: its height, the gap below it and the panel's padding.
    private static let headerAllowance: CGFloat = 70

    private var scrollLimit: CGFloat { max(160, model.panelMaxHeight - Self.headerAllowance) }

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            header

            // As tall as the cards, up to what the screen allows; beyond that (many displays, all expanded) it
            // scrolls. The scroll view is always there, so expanding a card never rebuilds the others.
            ScrollView(.vertical) {
                content
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, scrollLimit))
            // When there's more below, the last few points fade out instead of being cut off.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: contentHeight > scrollLimit ? 0.9 : 1),
                        .init(color: contentHeight > scrollLimit ? .clear : .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
            }
        }
        .padding(12)
        .frame(width: Metrics.panelWidth)
        .glassSurface(cornerRadius: Metrics.panelRadius)
        // Unfolds from the menu bar as it opens, like Control Center.
        .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .onChange(of: model.panelOpenCount) {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            appeared = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { appeared = true }
        }
        .animation(.luna, value: controller.displays.map(\.id))
        .animation(.luna, value: controller.disabled)
        .animation(.luna, value: showsKeysBanner)
        .animation(.luna, value: model.availableUpdate)
    }

    private var content: some View {
        VStack(spacing: Metrics.spacing) {
            if let version = model.availableUpdate {
                UpdateBanner(version: version)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if controller.displays.count > 1 {
                AllDisplaysCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            ForEach(controller.displays) { display in
                DisplayCard(display: display)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            ForEach(controller.disabled) { item in
                TurnedOffRow(item: item)
                    .transition(.opacity)
            }

            if controller.displays.isEmpty {
                Text("No displays found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .platter()
            }

            QuickSettings()

            if showsKeysBanner {
                KeysBanner()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var showsKeysBanner: Bool {
        !model.keysEnabled && !settings.dismissedKeysBanner && !controller.isPreview
            && controller.displays.contains { $0.kind != .builtin }
    }

    private var header: some View {
        HStack(spacing: 7) {
            LunaMark(size: 20)
            Text("Luna")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            CircleIconButton(systemImage: "gearshape.fill", help: "Settings and more") {
                PopUpMenu.show([
                    .init(title: "Settings…", symbol: "gearshape") { model.openSettings(.general) },
                    .init(
                        title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath",
                        enabled: model.updater.canCheck
                    ) { model.updater.checkForUpdates() },
                    .init(title: "About Luna", symbol: "info.circle") { model.openSettings(.about) },
                    .separator,
                    .init(title: "Quit Luna", symbol: "power") { model.quit() },
                ])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

/// One slider for every display at once.
private struct AllDisplaysCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        VStack(alignment: .leading, spacing: 7) {
            Text("All displays")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            GlassSlider(
                value: controller.averagePosition, icon: "sun.max.fill",
                label: "\(Int((controller.averagePosition * 100).rounded()))%",
                height: 26, accessibilityName: "Brightness of all displays"
            ) { controller.setAllPositions($0) }
        }
        .padding(10)
        .platter()
    }
}

/// A display Luna turned off, with the way back.
private struct TurnedOffRow: View {
    @Environment(AppModel.self) private var model
    var item: DisabledDisplay

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "display")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .semibold))
                Text("Turned off").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Turn On") { model.controller.turnOn(item) }
                .buttonStyle(ChipButtonStyle())
        }
        .padding(12)
        .platter()
    }
}

/// Auto brightness and rounded corners: the two app-wide switches.
private struct QuickSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let controller = model.controller
        VStack(spacing: 0) {
            HStack {
                Label {
                    Text("Auto")
                } icon: {
                    Image(systemName: "sun.horizon.fill").foregroundStyle(.orange.gradient)
                }
                .font(.system(size: 13, weight: .medium))
                Spacer()
                SegmentedPill(
                    options: autoOptions(canSync: controller.canSync), selection: settings.autoMode,
                    onSelect: { model.setAutoMode($0) })
            }
            .padding(.vertical, 9)

            if let caption = autoCaption {
                HStack(spacing: 4) {
                    Text(caption)
                    if settings.autoMode == .sun, settings.location?.approximate ?? true, !controller.isPreview {
                        Text("·")
                        Button("Use my location") { controller.auto.requestLocation() }
                            .buttonStyle(.link)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 9)
                .padding(.top, -3)
                .transition(.opacity)
            }

            Divider().opacity(0.5)

            HStack {
                Label {
                    Text("Rounded corners")
                } icon: {
                    Image(systemName: "viewfinder").foregroundStyle(.teal.gradient)
                }
                .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle(
                    "Rounded corners",
                    isOn: Binding(get: { settings.roundedCorners }, set: { model.setRoundedCorners($0) })
                )
                .toggleStyle(PanelSwitchStyle())
            }
            .padding(.vertical, 9)
        }
        .padding(.horizontal, 12)
        .platter()
        .animation(.luna, value: settings.autoMode)
    }

    private func autoOptions(canSync: Bool) -> [SegmentedPill<AutoMode>.Option] {
        var options: [SegmentedPill<AutoMode>.Option] = [.init(value: .off, title: "Off")]
        if canSync || model.settings.autoMode == .sync {
            options.append(.init(value: .sync, title: "Match Mac", symbol: "laptopcomputer"))
        }
        options.append(.init(value: .sun, title: "Sun", symbol: "sun.max.fill"))
        return options
    }

    private var autoCaption: String? {
        switch model.settings.autoMode {
        case .off: nil
        case .sync: "Following your Mac's display"
        case .sun: "Following daylight"
        }
    }
}

/// A newer Luna is waiting: one click shows what changed and installs it.
private struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    var version: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.green.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text("Luna \(version) is ready").font(.system(size: 12, weight: .semibold))
                Text("See what's new and install").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Update") {
                model.closePanel()
                model.updater.checkForUpdates()
            }
            .buttonStyle(ChipButtonStyle(prominent: true))
        }
        .padding(12)
        .platter()
    }
}

/// Asks once for Accessibility, which the brightness and volume keys need.
private struct KeysBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 15))
                .foregroundStyle(.blue.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text("Use your brightness keys").font(.system(size: 12, weight: .semibold))
                Text("For every display, with volume too").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Enable") { model.enableKeys() }
                .buttonStyle(ChipButtonStyle(prominent: true))
            Button {
                model.settings.dismissedKeysBanner = true
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .help("Not now (you can enable this in Settings › Keyboard)")
        }
        .padding(12)
        .platter()
    }
}

/// A small capsule button.
struct ChipButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, prominent: prominent)
    }

    private struct Chip: View {
        var configuration: Configuration
        var prominent: Bool
        @ViewState private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(
                    Capsule().fill(
                        prominent
                            ? AnyShapeStyle(Color.accentColor.gradient)
                            : AnyShapeStyle(Color.primary.opacity(hovering ? 0.15 : 0.09)))
                )
                .brightness(prominent && hovering ? 0.06 : 0)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

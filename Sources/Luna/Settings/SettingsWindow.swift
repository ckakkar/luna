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

import AppKit
import LunaCore
import SwiftUI

/// Shown once, on first launch: where Luna lives, and the two things worth turning on.
final class WelcomeWindowController {
    private var window: NSWindow?
    private let model: AppModel
    var onFinish: () -> Void = {}

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: WelcomeView { [weak self] in self?.finish() }.environment(model))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        model.settings.hasOnboarded = true
        window?.close()
        window = nil
        onFinish()
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.55, green: 0.5, blue: 1).opacity(0.5), .clear], center: .center,
                            startRadius: 8, endRadius: 100)
                    )
                    .frame(width: 200, height: 200)
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .padding(.top, 4)
            .padding(.bottom, -40)

            Text("Welcome to Luna")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Every display, as easy as your Mac's own.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            SettingsCard {
                SettingRow(
                    symbol: "menubar.arrow.up.rectangle", color: .purple, title: "Lives in your menu bar",
                    detail: "Click the moon at the top of the screen for brightness, volume and more."
                ) { EmptyView() }
                RowDivider()
                SettingRow(
                    symbol: "keyboard.fill", color: .blue, title: "Use your brightness keys",
                    detail: "On every display, with sound too. Needs Accessibility permission."
                ) {
                    if model.keysEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Button("Enable") { model.enableKeys() }
                            .buttonStyle(ChipButtonStyle(prominent: true))
                    }
                }
                RowDivider()
                SettingRow(
                    symbol: "power", color: .green, title: "Open at login",
                    detail: "So your displays are set up as soon as you sign in."
                ) {
                    CapsuleSwitch(label: "Open at login", isOn: $launchAtLogin)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 26)
            .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }

            Spacer(minLength: 18)

            Button(action: onDone) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.42, blue: 1.0), Color(red: 0.32, green: 0.36, blue: 0.92),
                                ],
                                startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: Color(red: 0.4, green: 0.38, blue: 1).opacity(0.45), radius: 12, y: 4)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 560)
        .background(AuroraBackground())
        .focusEffectDisabled()
        .animation(.luna, value: model.keysEnabled)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
    }
}

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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
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
            Image(nsImage: AppInfo.icon)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: .indigo.opacity(0.35), radius: 18, y: 8)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .padding(.top, 34)

            Text("Welcome to Luna")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .padding(.top, 16)
            Text("Every display, as easy as your Mac's own.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(spacing: 10) {
                step(
                    symbol: "menubar.arrow.up.rectangle", color: .purple, title: "Lives in your menu bar",
                    detail: "Click the moon at the top of the screen for brightness, volume and more."
                ) {
                    EmptyView()
                }
                step(
                    symbol: "keyboard.fill", color: .blue, title: "Use your brightness keys",
                    detail: "On every display, with sound too. Needs Accessibility permission."
                ) {
                    if model.keysEnabled {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                    } else {
                        Button("Enable") { model.enableKeys() }
                    }
                }
                step(
                    symbol: "power", color: .green, title: "Open at login",
                    detail: "So your displays are set up as soon as you sign in."
                ) {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 28)

            Spacer(minLength: 20)

            Button(action: onDone) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(width: 460, height: 520)
        .focusEffectDisabled()
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
    }

    private func step<Accessory: View>(
        symbol: String, color: Color, title: String, detail: String, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

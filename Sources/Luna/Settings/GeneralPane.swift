import AppKit
import LunaCore
import Observation
import SwiftUI

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

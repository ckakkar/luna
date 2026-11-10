import AppKit
import LunaCore
import Observation
import SwiftUI

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

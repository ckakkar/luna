import AppKit
import LunaCore
import Observation
import SwiftUI

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

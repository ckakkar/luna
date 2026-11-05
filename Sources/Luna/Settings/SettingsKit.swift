import AppKit
import LunaCore
import SwiftUI

/// The building blocks of Luna's Settings and welcome windows: the panel's design language (glass, capsule
/// switches and sliders, pills) laid out as cards of rows.

/// A soft aurora behind the window's content: an indigo glow at the top left, a warm one at the bottom right.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color(red: 0.42, green: 0.36, blue: 0.95).opacity(dark ? 0.32 : 0.18), .clear],
                center: .topLeading, startRadius: 20, endRadius: 520)
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.62, blue: 0.38).opacity(dark ? 0.16 : 0.13), .clear],
                center: .bottomTrailing, startRadius: 20, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// A rounded tile with a white symbol on a gradient, like System Settings' icons but softer.
struct IconTile: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// The top of each pane: a large tile, the pane's name and what it's for.
struct PaneHeader: View {
    var symbol: String
    var color: Color
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            IconTile(symbol: symbol, color: color, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }
}

/// A frosted card of rows, with an optional small heading above it and a note below.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.10 : 0.07), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 10, y: 3)
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One setting: an icon, a title, an explanation, and its control on the right.
struct SettingRow<Accessory: View>: View {
    var symbol: String?
    var color: Color = .accentColor
    var title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let symbol { IconTile(symbol: symbol, color: color) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                accessory
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

/// The hairline between rows, starting after the icon.
struct RowDivider: View {
    var inset: CGFloat = 54

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// A capsule switch bound to a value, in the panel's style.
struct CapsuleSwitch: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(PanelSwitchStyle())
            .labelsHidden()
    }
}

/// Two knobs on one capsule track: the lowest and highest brightness Luna uses.
struct RangeCapsule: View {
    var lower: Double
    var upper: Double
    var minimumGap = 0.05
    var onChange: (Double, Double) -> Void

    @Environment(\.colorScheme) private var scheme
    @ViewState private var dragging: Knob?

    private enum Knob {
        case lower, upper
    }

    private let height: CGFloat = 26

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - height)
            let lowerX = travel * lower
            let upperX = travel * upper
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.13 : 0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.75), .white], startPoint: .leading, endPoint: .trailing)
                    )
                    .overlay(Capsule().strokeBorder(Color.black.opacity(scheme == .dark ? 0 : 0.08), lineWidth: 0.5))
                    .frame(width: upperX - lowerX + height)
                    .offset(x: lowerX)
                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                knob(symbol: "sun.min.fill").offset(x: lowerX)
                knob(symbol: "sun.max.fill").offset(x: upperX)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let value = ((gesture.location.x - height / 2) / travel).clamped(to: 0...1)
                        let knob = dragging ?? (abs(value - lower) < abs(value - upper) ? .lower : .upper)
                        dragging = knob
                        switch knob {
                        case .lower: onChange(min(value, upper - minimumGap), upper)
                        case .upper: onChange(lower, max(value, lower + minimumGap))
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness range")
        .accessibilityValue("\(Int(lower * 100))% to \(Int(upper * 100))%")
    }

    private func knob(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(width: height, height: height)
    }
}

/// A small rounded label for facts about a display ("Hardware (DDC)", "XDR").
struct StatusChip: View {
    var text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(tint.opacity(0.13)))
    }
}

/// A card section that opens and closes, for the advanced options.
struct Disclosure<Content: View>: View {
    var title: String
    var symbol: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.luna) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: symbol, color: .gray)
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                RowDivider()
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

extension View {
    /// The width Settings content reads best at, centred in wider windows.
    func paneWidth() -> some View {
        frame(maxWidth: 600).frame(maxWidth: .infinity)
    }
}

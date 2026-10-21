import AppKit
import SwiftUI

enum Metrics {
    static let panelWidth: CGFloat = 320
    static let panelRadius: CGFloat = 24
    static let cardRadius: CGFloat = 17
    static let sliderHeight: CGFloat = 30
    static let spacing: CGFloat = 8
    /// Transparent space around the panel inside its window, so the glass's soft shadow isn't cut off.
    static let panelMargin: CGFloat = 16
}

enum Palette {
    /// The fill of a slider in the normal range: Control Center white.
    static let fill = Color.white
    /// Below 0%: moonlight.
    static let dim = LinearGradient(
        colors: [Color(red: 0.35, green: 0.40, blue: 0.86), Color(red: 0.52, green: 0.50, blue: 0.95)],
        startPoint: .leading, endPoint: .trailing)
    /// XDR: white warming into gold.
    static let boost = LinearGradient(
        colors: [.white, Color(red: 1.0, green: 0.86, blue: 0.55), Color(red: 1.0, green: 0.72, blue: 0.30)],
        startPoint: .leading, endPoint: .trailing)
    static let glow = Color(red: 1.0, green: 0.75, blue: 0.35)
    static let moon = Color(red: 0.55, green: 0.55, blue: 0.98)
}

extension View {
    /// The panel's surface: Liquid Glass on macOS 26 and later, the menu material before that.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(VisualEffect(material: .popover).clipShape(shape))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    /// A card sitting on the panel: a soft, slightly lifted platter.
    func platter(cornerRadius: CGFloat = Metrics.cardRadius) -> some View {
        modifier(Platter(cornerRadius: cornerRadius))
    }
}

private struct Platter: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Color.primary.opacity(scheme == .dark ? 0.07 : 0.045)))
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.35 : scheme == .dark ? 0.08 : 0.06), lineWidth: 0.5
                ))
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Plain buttons that dim while pressed, for icons and chips.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A small round icon button, like the ones in Control Center.
struct CircleIconButton: View {
    var systemImage: String
    var help: String
    var tint: Color = .primary
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.15 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension Animation {
    /// Springs, or a plain fade when Reduce Motion is on.
    @MainActor static var luna: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.84)
    }
}

/// SwiftUI's `State`. In the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode, so with just
/// the Command Line Tools the attribute doesn't compile; naming the property wrapper directly works with any
/// toolchain and behaves identically.
typealias ViewState<Value> = SwiftUI.State<Value>

/// A switch drawn by Luna, so it keeps its colour in the panel (macOS greys out its own switches in windows
/// of an app that isn't frontmost, which the menu bar panel never is).
struct PanelSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.luna) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(
                    configuration.isOn
                        ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.16))
                )
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// Luna's mark for the panel header: the menu bar crescent in moonlight colours.
struct LunaMark: View {
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: MoonGlyph.menuBarImage(brightness: 0.45))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.62, green: 0.60, blue: 1.0), Color(red: 1.0, green: 0.83, blue: 0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

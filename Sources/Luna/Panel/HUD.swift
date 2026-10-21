import AppKit
import LunaCore
import Observation
import SwiftUI

/// The on-screen indicator for the brightness and volume keys: a small glass capsule at the top right of the
/// display that changed, in the spot macOS uses for its own.
final class HUD {
    static let shared = HUD()

    @Observable
    final class State {
        var icon = "sun.max.fill"
        var value = 0.5
        var label = ""
        var tone = GlassSlider.Tone.normal
    }

    private let state = State()
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?
    private static let size = NSSize(width: 252, height: 50)

    func show(
        on displayID: CGDirectDisplayID, icon: String, value: Double, label: String, tone: GlassSlider.Tone = .normal
    ) {
        guard let screen = NSScreen.with(displayID: displayID) ?? NSScreen.main else { return }
        state.icon = icon
        state.value = value
        state.label = label
        state.tone = tone

        let window = self.window ?? makeWindow()
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - Self.size.width - 14, y: visible.maxY - Self.size.height - 10)
        if window.frame.origin != origin || !window.isVisible {
            window.setFrameOrigin(origin)
        }
        if !window.isVisible || window.alphaValue < 1 {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.12; window.animator().alphaValue = 1
            }
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let window = self?.window else { return }
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.35; window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { if window.alphaValue == 0 { window.orderOut(nil) } }
            }
        }
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        panel.contentView = NSHostingView(
            rootView: HUDView(state: state).frame(width: Self.size.width, height: Self.size.height))
        window = panel
        return panel
    }
}

private struct HUDView: View {
    var state: HUD.State

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.tone == .boost ? AnyShapeStyle(Palette.glow) : AnyShapeStyle(.primary))
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule()
                        .fill(fill)
                        .frame(width: max(6, geometry.size.width * state.value.clamped(to: 0...1)))
                        .shadow(color: state.tone == .boost ? Palette.glow.opacity(0.7) : .clear, radius: 5)
                }
            }
            .frame(height: 6)
            Text(state.label)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
                .contentTransition(.numericText(value: state.value))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 25)
        .animation(.luna, value: state.value)
    }

    private var fill: AnyShapeStyle {
        switch state.tone {
        case .normal: AnyShapeStyle(Color.primary)
        case .dim: AnyShapeStyle(Palette.dim)
        case .boost: AnyShapeStyle(Palette.boost)
        }
    }
}

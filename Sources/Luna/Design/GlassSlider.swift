import AppKit
import LunaCore
import SwiftUI

/// A Control Center slider: a thick capsule that fills from the left, with its icon inside the fill and the
/// value at the right. Click anywhere to jump, drag to adjust; ticks mark 0% and 100% when the track runs
/// past them, with a soft haptic bump as you cross.
struct GlassSlider: View {
    enum Tone {
        case normal, dim, boost
    }

    /// Position along the track, 0…1.
    var value: Double
    var icon: String
    /// For symbols with variable colour (speaker waves, sun rays).
    var iconValue: Double? = nil
    var label: String
    var tone: Tone = .normal
    var markers: [Double] = []
    var height: CGFloat = Metrics.sliderHeight
    var accessibilityName: String
    /// Clicking the icon does this instead of moving the slider (mute).
    var onIconTap: (() -> Void)? = nil
    var onChange: (Double) -> Void

    @ViewState private var dragging = false
    @ViewState private var hovering = false
    @ViewState private var tappingIcon = false
    @ViewState private var lastMarkerSide: [Int] = []
    @FocusState private var focused: Bool
    /// Shared by every slider: whether the keyboard is driving them (see `SliderKeyboard`).
    private var keyboard: SliderKeyboard { .shared }
    private var keyboardFocus: Bool { focused && keyboard.active }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(1, width - height)
            let fillWidth = height + travel * value.clamped(to: 0...1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity((scheme == .dark ? 0.13 : 0.15) + (hovering ? 0.03 : 0)))
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0), lineWidth: 1))

                ForEach(markers, id: \.self) { marker in
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 2, height: height * 0.34)
                        .offset(x: height / 2 + travel * marker - 1)
                }

                fill
                    .overlay(Capsule().strokeBorder(Color.black.opacity(scheme == .dark ? 0 : 0.07), lineWidth: 0.5))
                    .frame(width: fillWidth)
                    .shadow(
                        color: tone == .boost ? Palette.glow.opacity(0.55) : .black.opacity(0.10),
                        radius: tone == .boost ? 9 : 1.5, y: tone == .boost ? 0 : 0.5)

                iconView
                    .frame(width: height, height: height)

                // The value, drawn twice: on the track, and in the fill's colour where the fill covers it.
                valueText(Color.secondary)
                valueText(onFill.opacity(0.75))
                    .mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            // Changes from elsewhere (keys, auto brightness) glide; the slider follows a drag exactly.
            .animation(dragging ? nil : .smooth(duration: 0.28), value: value)
            .onHover { hovering = $0 }
            .gesture(drag(travel: travel))
        }
        .frame(height: height)
        // Keyboard: Tab to the slider, arrows to adjust (⌥ for fine steps), like the brightness keys.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay(
            Capsule().strokeBorder(Color.accentColor.opacity(keyboardFocus ? 0.85 : 0), lineWidth: 2).padding(-3)
        )
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard keyboardFocus else { return .ignored }
            let up = press.key == .rightArrow || press.key == .upArrow
            let step = press.modifiers.contains(.option) ? 1.0 / 64 : 1.0 / 16
            onChange((value + (up ? step : -step)).clamped(to: 0...1))
            return .handled
        }
        .scaleEffect(dragging ? 1.012 : 1)
        .animation(.luna, value: dragging)
        .animation(.luna, value: tone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / 32
            onChange((value + (direction == .increment ? step : -step)).clamped(to: 0...1))
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch tone {
        case .normal: Capsule().fill(Palette.fill)
        case .dim: Capsule().fill(Palette.dim)
        case .boost: Capsule().fill(Palette.boost)
        }
    }

    private var onFill: Color { tone == .dim ? .white : .black }

    private func valueText(_ color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(.numericText(value: value))
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var iconView: some View {
        Image(systemName: icon, variableValue: iconValue)
            .font(.system(size: height * 0.42, weight: .semibold))
            .foregroundStyle(onFill.opacity(tone == .dim ? 0.95 : 0.62))
            .contentTransition(.symbolEffect(.replace))
            .scaleEffect(tappingIcon ? 0.85 : 1)
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !dragging {
                    // The mouse took over: keyboard mode ends for every slider (no ring, arrows pass through),
                    // whichever one still has focus, so a click can't leave any reacting to the arrow keys.
                    keyboard.active = false
                    lastMarkerSide = markers.map { value >= $0 ? 1 : 0 }
                    if onIconTap != nil, gesture.startLocation.x < height {
                        tappingIcon = true
                    }
                }
                dragging = true
                if tappingIcon {
                    // Becomes a drag if the pointer travels.
                    if abs(gesture.translation.width) < 4 { return }
                    tappingIcon = false
                }
                let position = ((gesture.location.x - height / 2) / travel).clamped(to: 0...1)
                bumpIfCrossingMarker(position)
                onChange(position)
            }
            .onEnded { _ in
                if tappingIcon { onIconTap?() }
                tappingIcon = false
                dragging = false
            }
    }

    private func bumpIfCrossingMarker(_ position: Double) {
        let sides = markers.map { position >= $0 ? 1 : 0 }
        if sides != lastMarkerSide, !lastMarkerSide.isEmpty {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        lastMarkerSide = sides
    }
}

/// Whether the keyboard is driving the sliders. Pressing Tab in any of Luna's windows turns it on; any click
/// (on a slider, a button, the menu bar icon that opens the panel) turns it off, and so does the panel opening.
/// Only while it's on does the focused slider show its ring and take the arrow keys, so a slider macOS focused
/// on its own, or one the mouse last used, never moves under the arrow keys by surprise. It watches the input
/// itself rather than guessing from focus changes, which SwiftUI reports a moment after the event behind them.
@MainActor @Observable
final class SliderKeyboard {
    static let shared = SliderKeyboard()
    var active = false
    @ObservationIgnored private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown], handler: sliderKeyboardInput)
    }

    /// A key press: Tab (or Shift-Tab) turns keyboard mode on, other keys leave it. A click turns it off.
    fileprivate func note(keyDown: Bool, tab: Bool) {
        if !keyDown {
            active = false
        } else if tab {
            active = true
        }
    }
}

/// Local event monitors run on the main thread; the handler is built outside the main actor all the same, as
/// every macOS callback in Luna is (a closure made inside a main-actor type traps if called off it).
nonisolated private func sliderKeyboardInput(_ event: NSEvent) -> NSEvent? {
    let keyDown = event.type == .keyDown
    let tab = keyDown && event.keyCode == 48
    MainActor.assumeIsolated { SliderKeyboard.shared.note(keyDown: keyDown, tab: tab) }
    return event
}

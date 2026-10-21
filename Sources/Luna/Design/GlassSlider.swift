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
    @ViewState private var tappingIcon = false
    @ViewState private var lastMarkerSide: [Int] = []
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(1, width - height)
            let fillWidth = height + travel * value.clamped(to: 0...1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.13 : 0.11))
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0), lineWidth: 1))

                ForEach(markers, id: \.self) { marker in
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 2, height: height * 0.34)
                        .offset(x: height / 2 + travel * marker - 1)
                }

                fill
                    .frame(width: fillWidth)
                    .shadow(
                        color: tone == .boost ? Palette.glow.opacity(0.55) : .black.opacity(0.10),
                        radius: tone == .boost ? 9 : 1.5, y: tone == .boost ? 0 : 0.5)

                HStack(spacing: 0) {
                    iconView
                        .frame(width: height, height: height)
                    Spacer(minLength: 4)
                    Text(label)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(fillWidth > width - 38 ? onFill.opacity(0.75) : Color.secondary)
                        .contentTransition(.numericText(value: value))
                        .padding(.trailing, 11)
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(drag(travel: travel))
        }
        .frame(height: height)
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

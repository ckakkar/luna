import SwiftUI

/// A compact capsule switch whose selection slides between options, like the toggles in Control Center.
struct SegmentedPill<Value: Hashable>: View {
    struct Option: Identifiable {
        var value: Value
        var title: String
        var symbol: String?
        /// A special look when selected (XDR glows).
        var glow = false
        var id: Value { value }
    }

    var options: [Option]
    var selection: Value
    var onSelect: (Value) -> Void
    var height: CGFloat = 24

    @Namespace private var namespace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.luna) { onSelect(option.value) }
                } label: {
                    HStack(spacing: 4) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                        }
                        Text(option.title)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: height)
                    .foregroundStyle(selected ? Color.black.opacity(0.78) : Color.secondary)
                    .background {
                        if selected {
                            Capsule()
                                .fill(option.glow ? AnyShapeStyle(Palette.boost) : AnyShapeStyle(Color.white))
                                .shadow(
                                    color: option.glow ? Palette.glow.opacity(0.6) : .black.opacity(0.12),
                                    radius: option.glow ? 7 : 1.5, y: option.glow ? 0 : 0.5
                                )
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.07)))
    }
}

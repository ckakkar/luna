import AppKit
import LunaCore
import Observation
import SwiftUI

struct AutoBrightnessPane: View {
    @Environment(AppModel.self) private var model
    @ViewState private var forgot = false

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(
                symbol: "sun.horizon.fill", color: .orange, title: "Auto Brightness",
                subtitle: "Let brightness follow the light, and learn where you like it.")

            HStack(spacing: 12) {
                ModeTile(
                    mode: .off, title: "Off", symbol: "hand.raised.fill", color: .gray,
                    detail: "Brightness stays where you put it.")
                ModeTile(
                    mode: .sync, title: "Match Mac", symbol: "laptopcomputer", color: .blue,
                    detail: model.controller.canSync
                        ? "Follows your Mac's display, which follows the room."
                        : "Needs a built-in or Apple display and one more.",
                    enabled: model.controller.canSync || settings.autoMode == .sync)
                ModeTile(
                    mode: .sun, title: "Sun", symbol: "sun.max.fill", color: .orange,
                    detail: "Rises in the morning, falls in the evening.")
            }

            if settings.autoMode == .sun {
                SettingsCard(title: "Today") {
                    DaylightGraph(location: settings.location ?? AutoBrightness.approximateLocation())
                        .frame(height: 150)
                        .padding(14)
                    RowDivider(inset: 14)
                    if let location = settings.location, !location.approximate {
                        SettingRow(
                            symbol: "location.fill", color: .blue, title: "Using your location",
                            detail: "Only on this Mac, to know when the sun rises and sets."
                        ) { EmptyView() }
                    } else {
                        SettingRow(
                            symbol: "location.slash.fill", color: .gray, title: "Guessing from your time zone",
                            detail: "Good to within an hour or so of real sunrise and sunset."
                        ) {
                            Button("Use My Location") { model.controller.auto.requestLocation() }
                                .buttonStyle(ChipButtonStyle(prominent: true))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingsCard(
                footer:
                    "Move a slider while auto brightness is on and Luna remembers: next time, at that light, it goes where you put it."
            ) {
                SettingRow(symbol: "brain.head.profile", color: .pink, title: "Forget my adjustments") {
                    Button(forgot ? "Forgotten" : "Forget") {
                        model.controller.store.forgetLearnedCurves()
                        for display in model.controller.displays {
                            display.updateSettings {
                                $0.syncCurve = DisplaySettings().syncCurve
                                $0.sunCurve = DisplaySettings().sunCurve
                            }
                        }
                        forgot = true
                        model.controller.auto.update()
                    }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(forgot)
                }
            }
        }
        .animation(.luna, value: settings.autoMode)
    }
}

/// One auto-brightness mode, as a large tile that lights up when chosen.
private struct ModeTile: View {
    var mode: AutoMode
    var title: String
    var symbol: String
    var color: Color
    var detail: String
    var enabled = true

    @Environment(AppModel.self) private var model
    @ViewState private var hovering = false

    var body: some View {
        let selected = model.settings.autoMode == mode
        Button {
            withAnimation(.luna) { model.setAutoMode(mode) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: symbol, color: color, size: 34)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.16 : 0.08),
                        lineWidth: selected ? 2 : 0.5)
            )
            .shadow(color: selected ? Color.accentColor.opacity(0.25) : .clear, radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Today's daylight as a sky: night at the edges, the sun's arc through the day, and where it is now.
struct DaylightGraph: View {
    var location: SavedLocation

    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let samples = (0...96).map { i -> Double in
            Solar.daylight(
                at: start.addingTimeInterval(Double(i) * 900), latitude: location.latitude,
                longitude: location.longitude)
        }
        let now = Date().timeIntervalSince(start) / 86400
        let (sunrise, sunset) = sunTimes(from: start)

        VStack(spacing: 8) {
            Canvas { context, size in
                let sky = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12, style: .continuous)
                context.clip(to: sky)
                // Night to day across the hours, following the daylight.
                let stops = samples.enumerated().map { i, value in
                    Gradient.Stop(
                        color: Color(
                            red: 0.10 + 0.25 * value, green: 0.12 + 0.42 * value, blue: 0.32 + 0.45 * value),
                        location: Double(i) / 96)
                }
                context.fill(
                    sky,
                    with: .linearGradient(
                        Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))

                func point(_ i: Int, _ value: Double) -> CGPoint {
                    CGPoint(x: size.width * Double(i) / 96, y: size.height * (1 - value * 0.78) - 10)
                }
                var arc = Path()
                for (i, value) in samples.enumerated() {
                    i == 0 ? arc.move(to: point(i, value)) : arc.addLine(to: point(i, value))
                }
                var area = arc
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 1, green: 0.78, blue: 0.42).opacity(0.55), .clear]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(arc, with: .color(Color(red: 1, green: 0.82, blue: 0.5)), lineWidth: 2.5)

                let value = Solar.daylight(at: Date(), latitude: location.latitude, longitude: location.longitude)
                let sun = CGPoint(x: size.width * now, y: size.height * (1 - value * 0.78) - 10)
                context.stroke(
                    Path {
                        $0.move(to: CGPoint(x: sun.x, y: 0))
                        $0.addLine(to: CGPoint(x: sun.x, y: size.height))
                    }, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                for (radius, alpha) in [(18.0, 0.18), (11.0, 0.35)] {
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(alpha)))
                }
                context.fill(
                    Path(ellipseIn: CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12)), with: .color(.white))
            }
            HStack {
                if let sunrise {
                    Label(sunrise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
                }
                Spacer()
                Text("Now \(Date().formatted(date: .omitted, time: .shortened))")
                Spacer()
                if let sunset { Label(sunset.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill") }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's daylight")
        .accessibilityValue(
            [
                sunrise.map { "Sunrise \($0.formatted(date: .omitted, time: .shortened))" },
                sunset.map { "sunset \($0.formatted(date: .omitted, time: .shortened))" },
            ].compactMap { $0 }.joined(separator: ", "))
    }

    private func sunTimes(from start: Date) -> (Date?, Date?) {
        var sunrise: Date?
        var sunset: Date?
        var previous = Solar.elevation(at: start, latitude: location.latitude, longitude: location.longitude)
        for minute in stride(from: 5, through: 1440, by: 5) {
            let date = start.addingTimeInterval(Double(minute) * 60)
            let elevation = Solar.elevation(at: date, latitude: location.latitude, longitude: location.longitude)
            if previous < -0.83, elevation >= -0.83, sunrise == nil { sunrise = date }
            if previous >= -0.83, elevation < -0.83 { sunset = date }
            previous = elevation
        }
        return (sunrise, sunset)
    }
}

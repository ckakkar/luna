/// How bright a display is, across everything Luna can do to it.
public struct Level: Equatable, Sendable, Codable {
    /// Software dimming below 0%: 0 is none, 1 is as dark as Luna goes.
    public var dim: Double
    /// The normal range, 0–100%.
    public var brightness: Double
    /// XDR: 0 is plain 100%, 1 is the brightest the display can be pushed.
    public var boost: Double

    public init(dim: Double = 0, brightness: Double, boost: Double = 0) {
        self.dim = dim.clamped(to: 0...1)
        self.brightness = brightness.clamped(to: 0...1)
        self.boost = boost.clamped(to: 0...1)
    }

    /// One number across the three ranges: -1 (darkest) … 0 … 1 (100%) … 2 (full XDR).
    public var signed: Double { dim > 0 ? -dim : brightness + boost }

    public init(signed value: Double) {
        if value < 0 {
            self.init(dim: -value, brightness: 0)
        } else if value > 1 {
            self.init(brightness: 1, boost: value - 1)
        } else {
            self.init(brightness: value)
        }
    }
}

/// The brightness slider's track: an optional dimming zone on the left (below 0%), the normal 0–100% in the
/// middle, and an XDR zone on the right when XDR is on. Positions run 0…1 along the track.
public struct SliderZones: Equatable, Sendable {
    public static let dimShare = 0.14
    public static let boostShare = 0.26

    public var dimWidth: Double
    public var boostWidth: Double

    public init(dimming: Bool, xdr: Bool) {
        dimWidth = dimming ? Self.dimShare : 0
        boostWidth = xdr ? Self.boostShare : 0
    }

    /// Where 0% sits on the track.
    public var zeroPosition: Double { dimWidth }
    /// Where 100% sits on the track.
    public var fullPosition: Double { 1 - boostWidth }
    private var normalWidth: Double { 1 - dimWidth - boostWidth }

    public func level(at position: Double) -> Level {
        let p = position.clamped(to: 0...1)
        if dimWidth > 0, p < dimWidth { return Level(dim: 1 - p / dimWidth, brightness: 0) }
        if boostWidth > 0, p > fullPosition { return Level(brightness: 1, boost: (p - fullPosition) / boostWidth) }
        return Level(brightness: (p - dimWidth) / normalWidth)
    }

    public func position(of level: Level) -> Double {
        if level.dim > 0, dimWidth > 0 { return dimWidth * (1 - level.dim) }
        if level.boost > 0, boostWidth > 0 { return fullPosition + level.boost * boostWidth }
        return dimWidth + level.brightness * normalWidth
    }

    /// The level after `steps` presses of a brightness key (negative for down). A press is 1/16 of the normal
    /// range, as on macOS, and a quarter of the dimming or XDR zone; going past 0% or 100% only enters those
    /// zones when they're allowed.
    public static func step(
        _ level: Level, by steps: Double, allowDimming: Bool, allowBoost: Bool, normalStep: Double = 1.0 / 16
    ) -> Level {
        let zoneStep = 0.25
        var value = level
        var remaining = steps
        while abs(remaining) > 1e-9 {
            let direction = remaining > 0 ? 1.0 : -1.0
            let amount = min(abs(remaining), 1)
            remaining -= direction * amount
            if direction > 0 {
                if value.dim > 0 {
                    value.dim = max(0, value.dim - zoneStep * amount)
                } else if value.brightness < 1 {
                    value.brightness = min(1, value.brightness + normalStep * amount)
                } else if allowBoost {
                    value.boost = min(1, value.boost + zoneStep * amount)
                }
            } else {
                if value.boost > 0 {
                    value.boost = max(0, value.boost - zoneStep * amount)
                } else if value.brightness > 0 {
                    value.brightness = max(0, value.brightness - normalStep * amount)
                } else if allowDimming {
                    value.dim = min(1, value.dim + zoneStep * amount)
                }
            }
        }
        return Level(dim: value.dim, brightness: value.brightness, boost: value.boost)
    }
}

/// How much light software dimming lets through (1 is untouched), as a multiplier on the gamma table or
/// 1 - the opacity of a black overlay.
public enum SoftwareDimming {
    /// Darkest Luna goes on a display whose own backlight is already at its minimum.
    public static let hardwareFloor = 0.12
    /// Without hardware control, 0% leaves this much light, and the dimming zone goes down to `softwareFloor`.
    public static let softwareZero = 0.25
    public static let softwareFloor = 0.07

    public static func factor(_ level: Level, hardware: Bool) -> Double {
        if hardware {
            return 1 - (1 - hardwareFloor) * level.dim
        }
        if level.dim > 0 {
            return softwareZero - (softwareZero - softwareFloor) * level.dim
        }
        return softwareZero + (1 - softwareZero) * level.brightness
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

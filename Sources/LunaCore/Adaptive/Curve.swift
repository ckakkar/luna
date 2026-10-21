/// A rising curve that maps an input (the Mac's own brightness, or daylight) to a display's brightness, and
/// learns: when you adjust a display while auto brightness is on, that adjustment becomes a point the curve
/// passes through next time.
public struct Curve: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Sorted by x, always starting at x = 0 and ending at x = 1, never falling.
    public private(set) var points: [Point]

    /// Adjustments closer than this along x replace each other instead of piling up.
    static let spacing = 0.08

    public init(from start: Double, to end: Double) {
        points = [Point(x: 0, y: start.clamped(to: 0...1)), Point(x: 1, y: max(start, end).clamped(to: 0...1))]
    }

    public func value(at x: Double) -> Double {
        let x = x.clamped(to: 0...1)
        guard let upper = points.firstIndex(where: { $0.x >= x }) else { return points.last?.y ?? x }
        if upper == 0 { return points[0].y }
        let a = points[upper - 1]
        let b = points[upper]
        guard b.x > a.x, x < b.x else { return b.y }
        let t = (x - a.x) / (b.x - a.x)
        return a.y + (b.y - a.y) * t
    }

    /// Makes the curve pass through (x, y), dropping or flattening points that would make it fall.
    public mutating func learn(x: Double, y: Double) {
        let x = x.clamped(to: 0...1)
        let y = y.clamped(to: 0...1)

        if x < Self.spacing {
            points[0].y = y
        } else if x > 1 - Self.spacing {
            points[points.count - 1].y = y
        } else {
            points.removeAll { $0.x > 0 && $0.x < 1 && abs($0.x - x) < Self.spacing }
            points.append(Point(x: x, y: y))
            points.sort { $0.x < $1.x }
        }

        // Keep it rising: before the new point nothing may be higher, after it nothing lower. The ends move,
        // anything in between goes.
        let anchor = points.first { $0.x == x } ?? (x < Self.spacing ? points[0] : points[points.count - 1])
        points = points.compactMap { point in
            var point = point
            let isEnd = point.x == 0 || point.x == 1
            if point.x < anchor.x, point.y > anchor.y {
                guard isEnd else { return nil }
                point.y = anchor.y
            } else if point.x > anchor.x, point.y < anchor.y {
                guard isEnd else { return nil }
                point.y = anchor.y
            }
            return point
        }
    }
}

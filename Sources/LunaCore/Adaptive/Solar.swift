import Foundation

/// Where the sun is, from NOAA's solar position equations (Meeus, "Astronomical Algorithms"). Accurate to a
/// fraction of a degree, which is plenty for brightness.
public enum Solar {
    /// The sun's elevation above the horizon in degrees (negative below it), without refraction.
    public static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let sun = position(at: date)
        let minutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 60
        var solarTime = (minutes + sun.equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if solarTime < 0 { solarTime += 1440 }
        let hourAngle = radians(solarTime / 4 - 180)
        let lat = radians(latitude)
        let cosZenith = sin(lat) * sin(sun.declination) + cos(lat) * cos(sun.declination) * cos(hourAngle)
        return 90 - degrees(acos(cosZenith.clamped(to: -1...1)))
    }

    /// The highest the sun gets on the day of `date`, at solar noon.
    public static func noonElevation(on date: Date, latitude: Double) -> Double {
        90 - abs(latitude - degrees(position(at: date).declination))
    }

    /// 0 at night, rising through dawn to 1 once the sun is well up, and back down at dusk. "Well up" is
    /// measured against how high the sun gets that day, so winter days still reach full daylight.
    public static func daylight(at date: Date, latitude: Double, longitude: Double) -> Double {
        let elevation = elevation(at: date, latitude: latitude, longitude: longitude)
        let full = (noonElevation(on: date, latitude: latitude) * 0.6).clamped(to: 4...35)
        let start = -6.0  // civil twilight
        let t = ((elevation - start) / (full - start)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }

    private static func position(at date: Date) -> (declination: Double, equationOfTime: Double) {
        let julianDay = date.timeIntervalSince1970 / 86400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36525

        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = radians(meanAnomaly)
        let center =
            sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
        let omega = radians(125.04 - 1934.136 * t)
        let apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = radians(meanObliquity + 0.00256 * cos(omega))

        let declination = asin(sin(obliquity) * sin(apparentLongitude))
        let y = pow(tan(obliquity / 2), 2)
        let l0 = radians(meanLongitude)
        let equationOfTime =
            4
            * degrees(
                y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
                    - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))
        return (declination, equationOfTime)
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

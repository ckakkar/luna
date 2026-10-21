import Foundation
import Testing

@testable import LunaCore

@Suite struct SolarTests {
    static func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    // London, 21 June 2026: sunrise 04:43 BST (03:43 UTC), when the sun's centre is 0.83° below the horizon.
    @Test func sunriseInLondon() {
        let elevation = Solar.elevation(at: Self.utc("2026-06-21T03:43:00Z"), latitude: 51.5074, longitude: -0.1278)
        #expect(abs(elevation - -0.83) < 0.6)
    }

    @Test func middayAtTheEquinox() {
        // The sun stands almost straight above the equator at noon.
        let elevation = Solar.elevation(at: Self.utc("2026-03-20T12:07:00Z"), latitude: 0, longitude: 0)
        #expect(elevation > 89)
    }

    @Test func noonElevationMatchesTheSunAtNoon() {
        let date = Self.utc("2026-12-21T12:00:00Z")
        let noon = Solar.noonElevation(on: date, latitude: 51.5)
        #expect(abs(noon - 15.05) < 0.3)
        #expect(abs(Solar.elevation(at: Self.utc("2026-12-21T11:58:00Z"), latitude: 51.5, longitude: 0) - noon) < 0.3)
    }

    @Test func daylightRunsFromNightToDay() {
        let night = Solar.daylight(at: Self.utc("2026-06-21T00:00:00Z"), latitude: 51.5, longitude: 0)
        let noon = Solar.daylight(at: Self.utc("2026-06-21T12:00:00Z"), latitude: 51.5, longitude: 0)
        let winterNoon = Solar.daylight(at: Self.utc("2026-12-21T12:00:00Z"), latitude: 51.5, longitude: 0)
        #expect(night == 0)
        #expect(noon == 1)
        #expect(winterNoon == 1)
    }

    @Test func daylightRisesThroughTheMorning() {
        let start = Self.utc("2026-06-21T02:00:00Z")
        let values = (0..<40).map {
            Solar.daylight(at: start.addingTimeInterval(Double($0) * 300), latitude: 51.5, longitude: 0)
        }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.first == 0 && values.last! > 0.3)
    }
}

@Suite struct ApproximateLocationTests {
    let winter = SolarTests.utc("2026-01-15T12:00:00Z")
    let summer = SolarTests.utc("2026-07-15T12:00:00Z")

    @Test func longitudeComesFromTheStandardOffset() {
        let london = AutoBrightness.approximateLocation(timeZone: TimeZone(identifier: "Europe/London")!, date: summer)
        #expect(london.longitude == 0 && london.latitude == 40 && london.approximate)
        let india = AutoBrightness.approximateLocation(timeZone: TimeZone(identifier: "Asia/Kolkata")!, date: winter)
        #expect(india.longitude == 82.5)
    }

    @Test func southernTimeZonesGetASouthernLatitude() {
        let sydney = AutoBrightness.approximateLocation(
            timeZone: TimeZone(identifier: "Australia/Sydney")!, date: winter)
        #expect(sydney.latitude < 0 && sydney.longitude == 150)
    }
}

@Suite struct SettingsTests {
    @Test func olderSavedSettingsGetNewDefaults() throws {
        let saved: [String: Any] = ["nickname": "Desk", "slowDDC": true]
        let settings = try #require(DisplayStore.decodeMergingDefaults(saved))
        #expect(settings.nickname == "Desk" && settings.slowDDC)
        #expect(settings.linkContrast && settings.maxBrightness == 1)
    }

    @Test @MainActor func displayStoreKeepsSettingsPerDisplay() {
        let defaults = UserDefaults(suiteName: "luna.tests.\(UUID())")!
        let store = DisplayStore(defaults: defaults)
        var settings = store["a"]
        settings.nickname = "Left"
        store["a"] = settings
        store.flush()
        #expect(DisplayStore(defaults: defaults)["a"].nickname == "Left")
        #expect(DisplayStore(defaults: defaults)["b"].nickname == nil)
    }

    @Test @MainActor func appSettingsPersist() {
        let defaults = UserDefaults(suiteName: "luna.tests.\(UUID())")!
        let settings = AppSettings(defaults: defaults)
        settings.autoMode = .sun
        settings.shortcuts[.toggleXDR] = KeyCombo(keyCode: 7, modifiers: 256)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.autoMode == .sun)
        #expect(reloaded.shortcuts[.toggleXDR] == KeyCombo(keyCode: 7, modifiers: 256))
    }
}

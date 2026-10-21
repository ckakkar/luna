import Foundation
import Testing

@testable import LunaCore

@Suite struct SliderZoneTests {
    let all = SliderZones(dimming: true, xdr: true)
    let plain = SliderZones(dimming: false, xdr: false)

    @Test func plainTrackIsJustZeroToHundred() {
        #expect(plain.level(at: 0) == Level(brightness: 0))
        #expect(plain.level(at: 0.5) == Level(brightness: 0.5))
        #expect(plain.level(at: 1) == Level(brightness: 1))
    }

    @Test func dimmingZoneSitsLeftOfZero() {
        #expect(all.level(at: 0) == Level(dim: 1, brightness: 0))
        #expect(all.level(at: all.zeroPosition) == Level(brightness: 0))
        #expect(abs(all.level(at: all.zeroPosition / 2).dim - 0.5) < 1e-9)
    }

    @Test func xdrZoneSitsRightOfHundred() {
        #expect(all.level(at: all.fullPosition) == Level(brightness: 1))
        #expect(all.level(at: 1) == Level(brightness: 1, boost: 1))
    }

    @Test(arguments: Array(stride(from: 0.0, through: 1.0, by: 0.05)))
    func positionsRoundTrip(position: Double) {
        #expect(abs(all.position(of: all.level(at: position)) - position) < 1e-9)
        #expect(abs(plain.position(of: plain.level(at: position)) - position) < 1e-9)
    }

    @Test func clampsOutOfRangePositions() {
        #expect(plain.level(at: -1) == Level(brightness: 0))
        #expect(plain.level(at: 2) == Level(brightness: 1))
    }

    @Test func signedValueRoundTrips() {
        for level in [Level(dim: 0.4, brightness: 0), Level(brightness: 0.3), Level(brightness: 1, boost: 0.7)] {
            #expect(Level(signed: level.signed) == level)
        }
    }

    @Test func sixteenKeyPressesCoverTheNormalRange() {
        let top = SliderZones.step(Level(brightness: 0), by: 16, allowDimming: true, allowBoost: false)
        #expect(abs(top.brightness - 1) < 1e-9 && top.boost == 0)
    }

    @Test func keysEnterDimmingOnlyWhenAllowed() {
        let zero = Level(brightness: 0)
        #expect(
            SliderZones.step(zero, by: -1, allowDimming: true, allowBoost: false) == Level(dim: 0.25, brightness: 0))
        #expect(SliderZones.step(zero, by: -1, allowDimming: false, allowBoost: false) == zero)
    }

    @Test func keysEnterAndLeaveXDR() {
        let full = Level(brightness: 1)
        let boosted = SliderZones.step(full, by: 2, allowDimming: false, allowBoost: true)
        #expect(boosted == Level(brightness: 1, boost: 0.5))
        #expect(SliderZones.step(boosted, by: -3, allowDimming: false, allowBoost: true).brightness < 1)
        #expect(SliderZones.step(full, by: 1, allowDimming: false, allowBoost: false) == full)
    }

    @Test func fineStepsAreAQuarter() {
        let fine = SliderZones.step(Level(brightness: 0.5), by: 0.25, allowDimming: true, allowBoost: true)
        #expect(abs(fine.brightness - (0.5 + 1.0 / 64)) < 1e-9)
    }
}

@Suite struct SoftwareDimmingTests {
    @Test func hardwareDisplaysOnlyDimBelowZero() {
        #expect(SoftwareDimming.factor(Level(brightness: 0.3), hardware: true) == 1)
        #expect(SoftwareDimming.factor(Level(dim: 1, brightness: 0), hardware: true) == SoftwareDimming.hardwareFloor)
    }

    @Test func softwareDisplaysDimAcrossTheWholeTrack() {
        #expect(SoftwareDimming.factor(Level(brightness: 1), hardware: false) == 1)
        #expect(SoftwareDimming.factor(Level(brightness: 0), hardware: false) == SoftwareDimming.softwareZero)
        #expect(SoftwareDimming.factor(Level(dim: 1, brightness: 0), hardware: false) == SoftwareDimming.softwareFloor)
    }

    @Test func darkerAllTheWayDown() {
        let zones = SliderZones(dimming: true, xdr: false)
        for hardware in [true, false] {
            let factors = stride(from: 0.0, through: 1.0, by: 0.01).map {
                SoftwareDimming.factor(zones.level(at: $0), hardware: hardware)
            }
            #expect(zip(factors, factors.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }
}

@Suite struct CurveTests {
    @Test func startsAsAStraightLine() {
        let curve = Curve(from: 0, to: 1)
        #expect(curve.value(at: 0.25) == 0.25)
        #expect(curve.value(at: -1) == 0 && curve.value(at: 2) == 1)
    }

    @Test func passesThroughWhatItLearned() {
        var curve = Curve(from: 0, to: 1)
        curve.learn(x: 0.5, y: 0.8)
        #expect(curve.value(at: 0.5) == 0.8)
        #expect(abs(curve.value(at: 0.25) - 0.4) < 1e-9)
    }

    @Test func staysRising() {
        var curve = Curve(from: 0, to: 1)
        curve.learn(x: 0.3, y: 0.6)
        curve.learn(x: 0.7, y: 0.4)
        let values = stride(from: 0.0, through: 1.0, by: 0.01).map { curve.value(at: $0) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
        #expect(curve.value(at: 0.7) == 0.4)
        #expect(!curve.points.contains { $0.x == 0.3 })
    }

    @Test func nearbyAdjustmentsReplaceEachOther() {
        var curve = Curve(from: 0, to: 1)
        curve.learn(x: 0.5, y: 0.6)
        curve.learn(x: 0.53, y: 0.65)
        #expect(curve.points.count == 3)
        #expect(curve.value(at: 0.53) == 0.65)
    }

    @Test func adjustingNearTheEndsMovesThem() {
        var curve = Curve(from: 0.35, to: 0.9)
        curve.learn(x: 0.02, y: 0.1)
        curve.learn(x: 0.99, y: 1)
        #expect(curve.points.map(\.y) == [0.1, 1])
    }

    @Test func endsFollowToKeepItRising() {
        var curve = Curve(from: 0.35, to: 0.9)
        curve.learn(x: 0.5, y: 0.2)
        #expect(curve.value(at: 0) == 0.2)
        curve.learn(x: 0.6, y: 0.95)
        #expect(curve.value(at: 1) == 0.95)
    }

    @Test func survivesEncoding() throws {
        var curve = Curve(from: 0, to: 1)
        curve.learn(x: 0.4, y: 0.7)
        let decoded = try JSONDecoder().decode(Curve.self, from: JSONEncoder().encode(curve))
        #expect(decoded == curve)
    }
}

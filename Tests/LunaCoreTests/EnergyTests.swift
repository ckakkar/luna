import AppKit
import CoreGraphics
import Foundation
import Observation
import Testing

@testable import LunaCore

@Suite @MainActor struct EnergyTests {
    @Test func unchangedWatchTicksReuseTheirBuffersWithoutWrites() {
        let tables = FakeGammaTables()
        var nudges = 0
        let dimmer = Dimmer(gamma: tables.access, gammaDidChange: { _ in nudges += 1 })
        dimmer.set(1.4, for: 700, method: .gamma)
        let initialReads = tables.reads.count

        for _ in 0..<120 { dimmer.restoreIfReset(700) }

        #expect(tables.writes.count == 1)
        #expect(nudges == 1)
        let checks = tables.reads.dropFirst(initialReads)
        #expect(checks.count == 120)
        // All three tables every time (macOS refuses a red-only read), into the same buffers.
        #expect(checks.allSatisfy { $0.capacity == 256 && $0.green && $0.blue })
        #expect(Set(checks.map(\.redAddress)).count == 1)
    }

    @Test func aResetRestoresTheExactOriginalScaledTablesOnce() {
        // The peak is deliberately inside the table. Checking only an endpoint would miss this reset.
        let tables = FakeGammaTables(
            profile: .init(red: [0, 0.95, 0.4], green: [0.1, 0.8, 0.7], blue: [0, 0.6, 0.9]))
        let dimmer = Dimmer(gamma: tables.access, gammaDidChange: { _ in })
        dimmer.set(1.6, for: 700, method: .gamma)
        tables.current[700] = tables.profile
        dimmer.restoreIfReset(700)

        #expect(tables.writes.count == 2)
        #expect(tables.writes.last?.table == tables.profile.scaled(by: 1.6))
        dimmer.restoreIfReset(700)
        #expect(tables.writes.count == 2)
    }

    @Test func unreadableOrEmptyTablesDoNotCauseWrites() {
        let tables = FakeGammaTables()
        let dimmer = Dimmer(gamma: tables.access, gammaDidChange: { _ in })
        dimmer.set(1.4, for: 700, method: .gamma)
        tables.readError = .failure
        dimmer.restoreIfReset(700)
        tables.readError = .success
        tables.emptyRead = true
        dimmer.restoreIfReset(700)
        #expect(tables.writes.count == 1)
    }

    @Test func resetThresholdAndChangedFactorsKeepTheirValues() {
        let tables = FakeGammaTables()
        let dimmer = Dimmer(gamma: tables.access, gammaDidChange: { _ in })
        dimmer.set(1.4, for: 700, method: .gamma)
        tables.current[700] = tables.profile.scaled(by: 1.395)
        dimmer.restoreIfReset(700)
        #expect(tables.writes.count == 1)
        tables.current[700] = tables.profile.scaled(by: 1.38)
        dimmer.restoreIfReset(700)
        #expect(tables.writes.count == 2)
        dimmer.set(0.4, for: 700, method: .gamma)
        #expect(tables.writes.last?.table == tables.profile.scaled(by: 0.4))
    }

    @Test func wakingRecapturesTheProfileWithoutCompoundingTheLift() {
        let tables = FakeGammaTables()
        let dimmer = Dimmer(gamma: tables.access, gammaDidChange: { _ in })
        dimmer.set(1.4, for: 700, method: .gamma)
        tables.profile = .init(red: [0, 0.3, 0.9], green: [0, 0.4, 0.8], blue: [0, 0.5, 0.7])
        dimmer.reapply()
        #expect(tables.restores == 1)
        #expect(tables.writes.last?.table == tables.profile.scaled(by: 1.4))
        dimmer.restoreIfReset(700)
        #expect(tables.writes.count == 2)
    }

    @Test func resettingOneDisplayReappliesTheOthers() {
        let tables = FakeGammaTables()
        let dimmer = Dimmer(gamma: tables.access, gammaDidChange: { _ in })
        dimmer.set(1.4, for: 700, method: .gamma)
        dimmer.set(0.4, for: 701, method: .gamma)
        dimmer.reset(700)
        #expect(tables.restores == 1)
        #expect(tables.current[700] == tables.profile)
        #expect(tables.current[701] == tables.profile.scaled(by: 0.4))
        let count = tables.reads.count
        dimmer.restoreIfReset(700)
        #expect(tables.reads.count == count)
        dimmer.resetAll()
        #expect(tables.restores == 2)
    }

    @Test func boostInputsFollowHeadroomWithoutChangingTheTransferCurve() {
        let open = Display.BoostInputs(multiplier: 2.2, headroom: 3, method: .gamma)
        #expect(!open.needsTrigger)
        #expect(abs(open.gammaFactor - pow(2.2, 1 / 2.2)) < 1e-12)
        let limited = Display.BoostInputs(multiplier: 2.2, headroom: 1.2, method: .gamma)
        #expect(limited.needsTrigger)
        #expect(abs(limited.gammaFactor - pow(1.2, 1 / 2.2)) < 1e-12)
        let closed = Display.BoostInputs(multiplier: 2.2, headroom: 1.05, method: .gamma)
        #expect(closed.gammaFactor == 1)
        #expect(open != limited)
        #expect(open == Display.BoostInputs(multiplier: 2.2, headroom: 3, method: .gamma))
    }

    @Test func boostEventsHopFromBackgroundNotificationsAndCanBeRemoved() async {
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        let changes = WriteLog()
        let observers = Display.observeBoostEnvironment(center: center, workspace: workspace) {
            changes.record("refresh")
        }
        // Deliver like macOS, from outside the main actor. A callback constructed in an actor-isolated
        // context would trap here under Swift 6, before it even got a chance to schedule the Task.
        let queue = DispatchQueue(label: "luna.tests.boost-events")
        queue.async {
            center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        }
        #expect(await Fixtures.eventually { changes.order.count == 4 })
        for (source, observer) in observers { source.removeObserver(observer) }
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        #expect(changes.order.count == 4)
    }

    @Test func glyphObservationSeesAnUnselectedDisplaysLevelChange() {
        let (controller, displays) = Fixtures.controller([(.builtin, .preview), (.external, .preview)])
        let changes = WriteLog()
        withObservationTracking {
            for display in controller.displays { _ = display.position }
        } onChange: {
            changes.record("level")
        }
        displays[1].setLevel(Level(brightness: 0.3), byUser: false)
        #expect(changes.order == ["level"])
    }

    @Test func glyphObservationSeesDisplayListAndZoneChanges() {
        let (controller, displays) = Fixtures.controller([(.builtin, .preview), (.external, .preview)])
        let changes = WriteLog()
        withObservationTracking {
            for display in controller.displays { _ = display.position }
        } onChange: {
            changes.record("list")
        }
        controller.setDisplaysForTesting([displays[1]])
        #expect(changes.order == ["list"])

        withObservationTracking {
            _ = displays[1].position
        } onChange: {
            changes.record("zone")
        }
        controller.settings.allowDimming.toggle()
        #expect(changes.order == ["list", "zone"])
    }
}

/// A colour-table backend with no CoreGraphics calls or windows. Each test has its own instance.
@MainActor private final class FakeGammaTables {
    struct Table: Equatable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]

        func scaled(by factor: CGGammaValue) -> Table {
            Table(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
        }
    }

    struct Read {
        var capacity: UInt32
        var green: Bool
        var blue: Bool
        var redAddress: UInt
    }

    var profile: Table
    var current: [CGDirectDisplayID: Table] = [:]
    var reads: [Read] = []
    var writes: [(display: CGDirectDisplayID, table: Table)] = []
    var restores = 0
    var readError = CGError.success
    var emptyRead = false

    init(profile: Table = .init(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])) {
        self.profile = profile
    }

    var access: Dimmer.GammaAccess {
        Dimmer.GammaAccess(
            read: { [self] display, capacity, red, green, blue, count in
                reads.append(
                    Read(capacity: capacity, green: green != nil, blue: blue != nil, redAddress: UInt(bitPattern: red)))
                guard readError == .success else { return readError }
                // Like CoreGraphics on a real display: without all three tables the read fails (error 1001).
                guard red != nil, green != nil, blue != nil else { return .failure }
                let table = current[display] ?? profile
                let size = emptyRead ? 0 : min(Int(capacity), table.red.count)
                count?.pointee = UInt32(size)
                for index in 0..<size {
                    red?[index] = table.red[index]
                    green?[index] = table.green[index]
                    blue?[index] = table.blue[index]
                }
                return .success
            },
            write: { [self] display, size, red, green, blue in
                let table = Table(
                    red: Array(UnsafeBufferPointer(start: red, count: Int(size))),
                    green: Array(UnsafeBufferPointer(start: green, count: Int(size))),
                    blue: Array(UnsafeBufferPointer(start: blue, count: Int(size))))
                current[display] = table
                writes.append((display, table))
                return .success
            },
            restore: { [self] in
                restores += 1
                for display in current.keys { current[display] = profile }
            })
    }
}

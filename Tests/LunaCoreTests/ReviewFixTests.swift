import CoreGraphics
import Foundation
import Testing

@testable import LunaCore

/// Regression tests for the issues from the code review (GitHub #5–#16).
@Suite @MainActor struct TurnOffTests {
    // #5
    @Test func twoQuickTurnOffsLeaveOneDisplayOn() {
        let (controller, displays) = Fixtures.controller([(.builtin, .preview), (.external, .preview)])
        controller.canSwitchDisplays = true
        var switchedOff: [CGDirectDisplayID] = []
        controller.setDisplayEnabled = { enabled, id in
            if !enabled { switchedOff.append(id) }
            return true
        }
        controller.turnOff(displays[0])
        // The second click comes before any refresh.
        #expect(!controller.canTurnOff(displays[1]))
        controller.turnOff(displays[1])
        #expect(switchedOff == [displays[0].id])
        #expect(controller.displays.map(\.id) == [displays[1].id])
    }
}

@Suite struct DDCFairnessTests {
    // #7
    @Test func monitorsTakeTurnsOnTheSharedQueue() async {
        let log = WriteLog()
        let a = DDCChannel(transport: FakeTransport(name: "A", log: log))
        let b = DDCChannel(transport: FakeTransport(name: "B", log: log))
        a.timing = .instant
        b.timing = .instant
        // Hold A for a moment so all its writes are waiting before B's arrives.
        a.pause(for: 0.2)
        for vcp in UInt8(0x20)..<0x2A { a.write(vcp, value: 50) }
        b.write(VCP.brightness, value: 50)
        let done = await Fixtures.eventually { log.order.count == 22 }
        #expect(done)
        // Each write goes out twice; B's comes right after A's first, not after all ten.
        #expect(log.order.firstIndex(of: "B") == 2)
    }

    @Test func aDraggedSliderStillCoalesces() async {
        let transport = FakeTransport()
        let channel = DDCChannel(transport: transport)
        channel.timing = .instant
        channel.pause(for: 0.1)
        for value in UInt16(0)..<50 { channel.write(VCP.brightness, value: value) }
        _ = await Fixtures.eventually { !transport.writes.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
        // Only the latest value is sent (twice).
        #expect(transport.writes.map(\.value) == [49, 49])
    }
}

@Suite @MainActor struct BrightnessKeyTests {
    // #8
    @Test func shortcutsChangeAppleDisplaysToo() {
        let (controller, displays) = Fixtures.controller([(.builtin, .apple)])
        let display = displays[0]
        display.setLevel(Level(brightness: 0.5), byUser: false)
        let changed = BrightnessKeys.press(
            up: true, fine: false, fromMediaKey: false, targets: [display], settings: controller.settings)
        #expect(changed.count == 1)
        #expect(abs(display.level.brightness - (0.5 + 1.0 / 16)) < 1e-9)
    }

    @Test func mediaKeysForOnlyAppleDisplaysAreLeftToMacOS() {
        let (controller, displays) = Fixtures.controller([(.builtin, .apple)])
        displays[0].setLevel(Level(brightness: 0.5), byUser: false)
        let changed = BrightnessKeys.press(
            up: true, fine: false, fromMediaKey: true, targets: displays, settings: controller.settings)
        #expect(changed.isEmpty)
        #expect(displays[0].level.brightness == 0.5)
    }

    @Test func mediaKeysForAllDisplaysChangeTheAppleOneToo() {
        let (controller, displays) = Fixtures.controller([(.builtin, .apple), (.external, .preview)])
        for display in displays { display.setLevel(Level(brightness: 0.5), byUser: false) }
        let changed = BrightnessKeys.press(
            up: false, fine: false, fromMediaKey: true, targets: displays, settings: controller.settings)
        #expect(changed.count == 2)
        #expect(displays.allSatisfy { abs($0.level.brightness - (0.5 - 1.0 / 16)) < 1e-9 })
    }

    @Test func goingBelowZeroIsLunasJob() {
        let (controller, displays) = Fixtures.controller([(.builtin, .apple)])
        displays[0].setLevel(Level(brightness: 0), byUser: false)
        #expect(!BrightnessKeys.macOSHandles(displays[0], up: false, settings: controller.settings))
        #expect(BrightnessKeys.macOSHandles(displays[0], up: true, settings: controller.settings))
    }
}

@Suite @MainActor struct AnimationTests {
    // #9
    @Test func outsideChangesReachTheSliderAfterAGlide() async {
        let (_, displays) = Fixtures.controller([(.builtin, .preview)])
        let display = displays[0]
        display.setLevel(Level(brightness: 0.2), byUser: false)
        display.animate(to: Level(brightness: 0.7), duration: 0.1)
        #expect(await Fixtures.eventually { !display.isAnimating })
        #expect(abs(display.level.brightness - 0.7) < 1e-9)
        display.systemBrightnessChanged(0.4)
        #expect(abs(display.level.brightness - 0.4) < 1e-9)
    }

    @Test func choosingXDRStopsAGlide() async {
        let (_, displays) = Fixtures.controller([(.builtin, .preview)])
        let display = displays[0]
        display.edrHeadroom = 3
        display.setLevel(Level(brightness: 0.8), byUser: false)
        display.animate(to: Level(brightness: 0.2), duration: 0.5)
        try? await Task.sleep(for: .milliseconds(80))
        display.setXDR(true)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(display.xdr)
        #expect(display.level.brightness == 1 && display.level.boost > 0)
    }
}

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
        // A queue of their own, as two monitors share the app's: other tests' slow fake monitors can't delay it.
        let queue = DispatchQueue(label: "luna.tests.fairness")
        let a = DDCChannel(transport: FakeTransport(name: "A", log: log), queue: queue)
        let b = DDCChannel(transport: FakeTransport(name: "B", log: log), queue: queue)
        a.timing = .instant
        b.timing = .instant
        // Hold A for a moment so all its writes are waiting before B's arrives.
        a.pause(for: 0.2)
        for vcp in UInt8(0x20)..<0x2A { a.write(vcp, value: 50) }
        b.write(VCP.brightness, value: 50)
        let done = await Fixtures.eventually(timeout: 10) { log.order.count == 22 }
        #expect(done)
        // Each write goes out twice; B's comes right after A's first, not after all ten.
        #expect(log.order.firstIndex(of: "B") == 2)
    }

    @Test func aDraggedSliderStillCoalesces() async {
        let transport = FakeTransport()
        let channel = DDCChannel(transport: transport, queue: DispatchQueue(label: "luna.tests.coalesce"))
        channel.timing = .instant
        channel.pause(for: 0.1)
        for value in UInt16(0)..<50 { channel.write(VCP.brightness, value: value) }
        _ = await Fixtures.eventually(timeout: 10) { !transport.writes.isEmpty }
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

@Suite @MainActor struct SoftwareModeDDCTests {
    // #10
    @Test func volumeAndContrastStillReachAMonitorDimmedInSoftware() async {
        let (_, displays) = Fixtures.controller([(.external, .software)])
        let display = displays[0]
        let transport = FakeTransport()
        let channel = DDCChannel(transport: transport)
        channel.timing = .instant
        display.ddc = channel
        display.hasVolume = true
        display.hasContrast = true

        display.setVolume(0.8)
        display.setContrast(0.6)
        display.setLevel(Level(brightness: 0.3), byUser: false)
        #expect(await Fixtures.eventually { transport.writes.count >= 4 })
        let codes = Set(transport.writes.map(\.vcp))
        #expect(codes.contains(VCP.volume) && codes.contains(VCP.contrast))
        // Brightness is software's job here.
        #expect(!codes.contains(VCP.brightness))
    }
}

@Suite @MainActor struct ControlMethodTests {
    // #12
    @Test func choosingHardwareLooksForDDC() async {
        let (controller, displays) = Fixtures.controller([(.external, .software)])
        let display = displays[0]
        display.settings.method = .software
        let transport = FakeTransport(values: [VCP.brightness: (40, 100)])
        var asked: [CGDirectDisplayID] = []
        controller.discoverChannels = { wanted, _ in
            asked += wanted.map(\.id)
            let channel = DDCChannel(transport: transport)
            channel.timing = .instant
            return [display.id: channel]
        }
        display.setMethod(.hardware)
        #expect(asked == [display.id])
        #expect(display.ddc != nil && display.control == .ddc)
        // The probe that follows reads the monitor's own brightness.
        #expect(await Fixtures.eventually { abs(display.level.brightness - 0.4) < 1e-9 })
    }
}

@Suite @MainActor struct DimmingSettingTests {
    // #14
    @Test func turningOffDimBelowZeroUndimsDisplays() {
        let (controller, displays) = Fixtures.controller([(.external, .preview), (.builtin, .preview)])
        displays[0].setLevel(Level(dim: 0.5, brightness: 0), byUser: false)
        displays[1].setLevel(Level(brightness: 0.6), byUser: false)
        controller.settings.allowDimming = false
        controller.dimmingSettingChanged()
        #expect(displays[0].level == Level(brightness: 0))
        #expect(displays[1].level == Level(brightness: 0.6))
    }
}

@Suite @MainActor struct LateResultTests {
    // #15
    @Test func aProbeDoesntUndoNewerChanges() async {
        let (_, displays) = Fixtures.controller([(.external, .ddc)])
        let display = displays[0]
        let transport = FakeTransport(
            values: [VCP.brightness: (50, 100), VCP.volume: (30, 100), VCP.contrast: (70, 100)], readDelay: 40_000)
        let channel = DDCChannel(transport: transport)
        channel.timing = .instant
        display.ddc = channel
        display.hasVolume = true

        let probe = Task { await display.probe() }
        try? await Task.sleep(for: .milliseconds(20))
        display.setVolume(0.8)
        display.setLevel(Level(brightness: 0.9))
        await probe.value
        #expect(display.volume == 0.8)
        #expect(abs(display.level.brightness - 0.9) < 1e-9)
        // Controls not touched take the monitor's values.
        #expect(abs(display.contrast - 0.7) < 1e-9)
    }

    @Test func testControlsKeepsAChangeMadeDuringTheTest() async {
        let (_, displays) = Fixtures.controller([(.builtin, .preview)])
        let display = displays[0]
        display.setLevel(Level(brightness: 0.6), byUser: false)
        let test = Task { await display.runTest() }
        try? await Task.sleep(for: .milliseconds(200))
        display.setLevel(Level(brightness: 0.95))
        _ = await test.value
        #expect(abs(display.level.brightness - 0.95) < 1e-9)
    }

    @Test func testControlsRestoresWhenNothingChanged() async {
        let (_, displays) = Fixtures.controller([(.builtin, .preview)])
        let display = displays[0]
        display.setLevel(Level(brightness: 0.6), byUser: false)
        _ = await display.runTest()
        #expect(abs(display.level.brightness - 0.6) < 1e-9)
    }
}

@Suite @MainActor struct ResetTests {
    // #16
    @Test func resetTurnsXDROff() {
        let (_, displays) = Fixtures.controller([(.builtin, .preview)])
        let display = displays[0]
        display.edrHeadroom = 3
        display.setXDR(true)
        #expect(display.level.boost > 0)
        display.resetSettings()
        #expect(!display.xdr && !display.settings.xdr)
        #expect(display.level.boost == 0)
    }
}

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

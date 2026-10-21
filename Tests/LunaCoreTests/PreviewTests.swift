import Foundation
import Testing

@testable import LunaCore

@Suite @MainActor struct PreviewTests {
    @Test func previewDisplaysKeepTheirSampleLevels() {
        let defaults = UserDefaults(suiteName: "luna.tests.\(UUID())")!
        let settings = AppSettings(defaults: defaults)
        let controller = DisplayController(
            settings: settings, store: DisplayStore(defaults: defaults), preview: PreviewDisplay.samples)
        let lg = controller.displays[1]
        #expect(lg.level == Level(brightness: 0.72))
        #expect(abs(lg.position - (0.14 + 0.72 * 0.86)) < 1e-9)
    }
}

@Suite @MainActor struct XDRTests {
    func display(_ kind: DisplayKind, headroom: Double) -> Display {
        let defaults = UserDefaults(suiteName: "luna.tests.\(UUID())")!
        let controller = DisplayController(
            settings: AppSettings(defaults: defaults), store: DisplayStore(defaults: defaults),
            preview: [PreviewDisplay(name: "Test", kind: kind, brightness: 0.5, edrHeadroom: headroom)])
        return controller.displays[0]
    }

    @Test func applePanelsGetXDR() {
        #expect(display(.builtin, headroom: 16).isXDRCapable)
        #expect(display(.apple, headroom: 6).isXDRCapable)
    }

    @Test func hdrMonitorsOnlyWhenAskedFor() {
        let monitor = display(.external, headroom: 10)
        #expect(!monitor.isXDRCapable)
        #expect(monitor.offersXDROnHDRMonitor)
        monitor.updateSettings { $0.allowXDR = true }
        #expect(monitor.isXDRCapable)
    }

    @Test func noHeadroomNoXDR() {
        #expect(!display(.builtin, headroom: 1).isXDRCapable)
        #expect(!display(.external, headroom: 1).offersXDROnHDRMonitor)
    }
}

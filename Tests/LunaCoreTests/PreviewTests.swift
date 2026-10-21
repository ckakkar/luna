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

import CoreGraphics
import Foundation

@testable import LunaCore

/// A DDC transport that records what's written and answers reads from a table, optionally slowly.
final class FakeTransport: DDCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _writes: [(vcp: UInt8, value: UInt16)] = []
    /// Replies to reads, by VCP code: (current, maximum). Codes not listed answer with a null message.
    var values: [UInt8: (UInt16, UInt16)]
    var readDelay: useconds_t
    let name: String
    let log: WriteLog?

    init(
        name: String = "fake", values: [UInt8: (UInt16, UInt16)] = [:], readDelay: useconds_t = 0, log: WriteLog? = nil
    ) {
        self.name = name
        self.values = values
        self.readDelay = readDelay
        self.log = log
    }

    var writes: [(vcp: UInt8, value: UInt16)] { lock.withLock { _writes } }

    func write(_ packet: [UInt8], source: UInt8) -> Bool {
        // Set VCP: [0x84, 0x03, vcp, high, low, checksum]
        let vcp = packet[2]
        let value = UInt16(packet[3]) << 8 | UInt16(packet[4])
        lock.withLock { _writes.append((vcp, value)) }
        log?.record(name)
        return true
    }

    func read(_ request: [UInt8], timing: DDCTiming) -> [UInt8]? {
        usleep(readDelay)
        let vcp = request[2]
        guard let (current, maximum) = lock.withLock({ values[vcp] }) else { return [0x6E, 0x80, 0xBE] }
        var bytes: [UInt8] = [
            0x6E, 0x88, 0x02, 0x00, vcp, 0x00, UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8),
            UInt8(current & 0xFF),
        ]
        bytes.append(DDCPacket.checksum(bytes, seed: 0x50))
        return bytes
    }
}

/// The order writes reach several fake monitors.
final class WriteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _order: [String] = []
    var order: [String] { lock.withLock { _order } }
    func record(_ name: String) { lock.withLock { _order.append(name) } }
}

extension DDCTiming {
    /// No waiting, one attempt: for tests.
    static let instant = DDCTiming(writeGap: 0, replyDelay: 0, attempts: 1)
}

@MainActor
enum Fixtures {
    static func defaults() -> UserDefaults { UserDefaults(suiteName: "luna.tests.\(UUID())")! }

    /// A controller with real (non-preview) displays built by hand, so their controls can be exercised.
    static func controller(_ displays: [(DisplayKind, Control)]) -> (DisplayController, [Display]) {
        let defaults = defaults()
        let settings = AppSettings(defaults: defaults)
        let store = DisplayStore(defaults: defaults)
        let controller = DisplayController(settings: settings, store: store, preview: [])
        let built = displays.enumerated().map { index, spec in
            Display(
                id: CGDirectDisplayID(500 + index), uuid: "test-\(index)", name: "Display \(index)", kind: spec.0,
                identity: DisplayIdentity(name: "Display \(index)"), control: spec.1, app: settings, store: store)
        }
        controller.setDisplaysForTesting(built)
        return (controller, built)
    }

    /// Waits until `condition` holds, up to `timeout` seconds.
    static func eventually(timeout: Double = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

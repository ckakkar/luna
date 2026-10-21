import CPrivate
import CoreGraphics
import Foundation
import IOKit

/// How patient to be with a monitor. Some need longer gaps between DDC messages.
public struct DDCTiming: Sendable {
    var writeGap: useconds_t
    var replyDelay: useconds_t
    var attempts: Int

    public static let normal = DDCTiming(writeGap: 10_000, replyDelay: 50_000, attempts: 5)
    public static let slow = DDCTiming(writeGap: 30_000, replyDelay: 120_000, attempts: 6)
}

/// One way of reaching a monitor's DDC/CI interface. Calls block, so they only run on `DDCChannel`'s queue.
protocol DDCTransport: Sendable {
    func write(_ packet: [UInt8], source: UInt8) -> Bool
    func read(_ request: [UInt8], timing: DDCTiming) -> [UInt8]?
}

/// Apple Silicon: the IOAVService behind a display's DCP.
final class AVServiceTransport: DDCTransport, @unchecked Sendable {
    // The service is a CF object used only from DDCChannel's serial queue.
    private let service: CFTypeRef

    init(service: CFTypeRef) {
        self.service = service
    }

    func write(_ packet: [UInt8], source: UInt8) -> Bool {
        LunaAVServiceWriteI2C(service, UInt32(DDCPacket.chipAddress), UInt32(source), packet, UInt32(packet.count))
            == kIOReturnSuccess
    }

    func read(_ request: [UInt8], timing: DDCTiming) -> [UInt8]? {
        guard write(request, source: DDCPacket.hostAddress) else { return nil }
        usleep(timing.replyDelay)
        var reply = [UInt8](repeating: 0, count: DDCPacket.replyLength)
        let result = LunaAVServiceReadI2C(
            service, UInt32(DDCPacket.chipAddress), 0, &reply, UInt32(DDCPacket.replyLength))
        return result == kIOReturnSuccess ? reply : nil
    }
}

/// Intel: I2C through the display's IOFramebuffer.
final class FramebufferTransport: DDCTransport {
    let displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func write(_ packet: [UInt8], source: UInt8) -> Bool {
        let bytes = [source] + packet
        return LunaIntelDDCTransfer(displayID, bytes, UInt32(bytes.count), nil, 0, 0) == kIOReturnSuccess
    }

    func read(_ request: [UInt8], timing: DDCTiming) -> [UInt8]? {
        let bytes = [DDCPacket.hostAddress] + request
        var reply = [UInt8](repeating: 0, count: DDCPacket.replyLength)
        let result = LunaIntelDDCTransfer(
            displayID, bytes, UInt32(bytes.count), &reply, UInt32(reply.count), UInt32(timing.replyDelay / 1000))
        return result == kIOReturnSuccess ? reply : nil
    }

    /// Whether this display has a framebuffer with an I2C bus at all (never true on Apple Silicon).
    static func exists(for displayID: CGDirectDisplayID) -> Bool {
        var reply = [UInt8](repeating: 0, count: DDCPacket.replyLength)
        let request = [DDCPacket.hostAddress] + DDCPacket.readRequest(VCP.brightness, includeSource: true)
        return LunaIntelDDCTransfer(displayID, request, UInt32(request.count), &reply, UInt32(reply.count), 40)
            != kIOReturnNotFound
    }
}

/// Talks to one monitor. Every display's traffic goes through one shared serial queue, because monitors and
/// the Mac's I2C hardware both misbehave when messages overlap.
///
/// Writes coalesce: while a write is waiting, a newer value for the same control replaces it, so dragging a
/// slider sends only as many messages as the monitor can take.
public final class DDCChannel: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "luna.ddc", qos: .userInitiated)

    private let transport: DDCTransport
    private let lock = NSLock()
    // Guarded by `lock`.
    private var pending: [UInt8: (value: UInt16, source: UInt8)] = [:]
    private var order: [UInt8] = []
    private var draining = false
    private var _timing = DDCTiming.normal
    private var pausedUntil = Date.distantPast

    init(transport: DDCTransport) {
        self.transport = transport
    }

    public var timing: DDCTiming {
        get { lock.withLock { _timing } }
        set { lock.withLock { _timing = newValue } }
    }

    /// Holds messages back for a while, e.g. after the Mac wakes, when monitors ignore or garble DDC.
    public func pause(for seconds: TimeInterval) {
        lock.withLock { pausedUntil = Date().addingTimeInterval(seconds) }
    }

    public func write(_ vcp: UInt8, value: UInt16, source: UInt8 = DDCPacket.hostAddress) {
        let start = lock.withLock {
            if pending[vcp] == nil { order.append(vcp) }
            pending[vcp] = (value, source)
            defer { draining = true }
            return !draining
        }
        if start { Self.queue.async { self.drain() } }
    }

    /// Reads a control's current and maximum value, retrying garbled replies.
    public func read(_ vcp: UInt8) async -> DDCPacket.Reply {
        await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: self.readNow(vcp)) }
        }
    }

    private func waitIfPaused() {
        let until = lock.withLock { pausedUntil }
        let wait = until.timeIntervalSinceNow
        if wait > 0 { usleep(useconds_t(min(wait, 10) * 1_000_000)) }
    }

    private func drain() {
        while true {
            waitIfPaused()
            let next: (vcp: UInt8, value: UInt16, source: UInt8, timing: DDCTiming)? = lock.withLock {
                while !order.isEmpty {
                    let vcp = order.removeFirst()
                    if let entry = pending.removeValue(forKey: vcp) { return (vcp, entry.value, entry.source, _timing) }
                }
                draining = false
                return nil
            }
            guard let next else { return }
            let packet = DDCPacket.write(next.vcp, value: next.value, source: next.source)
            // Monitors drop the odd message; sending each twice is what makes DDC feel reliable.
            var sent = false
            for _ in 0..<next.timing.attempts where !sent {
                usleep(next.timing.writeGap)
                sent = transport.write(packet, source: next.source)
                usleep(next.timing.writeGap)
                sent = transport.write(packet, source: next.source) || sent
            }
        }
    }

    private func readNow(_ vcp: UInt8) -> DDCPacket.Reply {
        waitIfPaused()
        let timing = self.timing
        var nulls = 0
        for attempt in 0..<timing.attempts {
            usleep(timing.writeGap)
            // Alternate between the two checksum forms monitors accept.
            let request = DDCPacket.readRequest(vcp, includeSource: attempt % 2 == 1)
            if let bytes = transport.read(request, timing: timing) {
                let reply = DDCPacket.parseReply(bytes, vcp: vcp)
                switch reply {
                case .value, .unsupported: return reply
                // A null can mean "not ready yet"; twice means "won't say".
                case .null: nulls += 1
                case .invalid: break
                }
                if nulls >= 2 { return .null }
            }
            usleep(20_000)
        }
        return nulls > 0 ? .null : .invalid
    }
}

/// Finds the DDC channels of external displays.
public enum DDCDiscovery {
    /// Builds a channel for each external display that has one, keyed by display ID.
    public static func channels(for displays: [(id: CGDirectDisplayID, identity: DisplayIdentity)])
        -> [CGDirectDisplayID: DDCChannel]
    {
        guard !displays.isEmpty else { return [:] }
        if LunaAVServiceIsAvailable() {
            let services = avServices()
            if !services.isEmpty {
                let assignment = DisplayMatching.assign(
                    displays: displays.map { ($0.id, $0.identity) }, framebuffers: services.map(\.identity))
                return assignment.mapValues { DDCChannel(transport: AVServiceTransport(service: services[$0].service)) }
            }
        }
        var channels: [CGDirectDisplayID: DDCChannel] = [:]
        for display in displays where FramebufferTransport.exists(for: display.id) {
            channels[display.id] = DDCChannel(transport: FramebufferTransport(displayID: display.id))
        }
        return channels
    }

    /// Walks the IORegistry: each external framebuffer (AppleCLCD2 / IOMobileFramebufferShim) is followed by
    /// the DCPAVServiceProxy that carries its DDC traffic.
    static func avServices() -> [(identity: FramebufferIdentity, service: CFTypeRef)] {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard
            IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
                == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [(FramebufferIdentity, CFTypeRef)] = []
        var framebuffer: FramebufferIdentity?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let name = registryName(entry)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                framebuffer = framebufferIdentity(entry)
            } else if name == "DCPAVServiceProxy", let current = framebuffer {
                framebuffer = nil
                guard property(entry, "Location") as? String == "External",
                    let service = LunaAVServiceCreate(entry)
                else { continue }
                found.append((current, service))
            }
        }
        return found
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(entry, &buffer)
        return string(buffer)
    }

    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func framebufferIdentity(_ entry: io_registry_entry_t) -> FramebufferIdentity? {
        guard let uuid = property(entry, "EDID UUID") as? String else { return nil }
        var path = [CChar](repeating: 0, count: 512)
        let location = IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS ? string(path) : nil
        let attributes =
            (property(entry, "DisplayAttributes") as? [String: Any])?["ProductAttributes"] as? [String: Any]
        return FramebufferIdentity(
            edidUUID: uuid, ioLocation: location, productName: attributes?["ProductName"] as? String,
            serial: (attributes?["SerialNumber"] as? NSNumber)?.intValue)
    }
}

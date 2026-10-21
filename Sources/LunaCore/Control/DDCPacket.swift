/// VCP codes from the VESA Monitor Control Command Set that Luna uses.
public enum VCP {
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    public static let inputSource: UInt8 = 0x60
    public static let volume: UInt8 = 0x62
    public static let mute: UInt8 = 0x8D
    public static let power: UInt8 = 0xD6
    /// LG monitors switch inputs with this manufacturer code, sent from host address 0x50.
    public static let lgInputSource: UInt8 = 0xF4
}

/// DDC/CI packets: Get and Set VCP Feature, with their checksums.
///
/// On the wire a packet is `display address (0x6E), source address, length|0x80, opcode, …, checksum`,
/// where the checksum XORs every byte before it. The display address is implied by the I2C transfer and
/// the source byte is sent separately (the "data address" of IOAVServiceWriteI2C), so the functions here
/// return the bytes after the source byte.
public enum DDCPacket {
    /// The display's 7-bit I2C address (0x6E >> 1).
    public static let chipAddress: UInt8 = 0x37
    public static let displayAddress: UInt8 = 0x6E
    /// The host's usual source address.
    public static let hostAddress: UInt8 = 0x51

    /// Set VCP Feature: `[0x84, 0x03, vcp, high, low, checksum]`.
    public static func write(_ vcp: UInt8, value: UInt16, source: UInt8 = hostAddress) -> [UInt8] {
        var bytes: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)]
        bytes.append(checksum(bytes, seed: displayAddress ^ source))
        return bytes
    }

    /// Get VCP Feature: `[0x82, 0x01, vcp, checksum]`.
    ///
    /// Monitors on Apple Silicon answer reads whose checksum leaves out the source byte, which is what
    /// MonitorControl and Lunar send; `includeSource` gives the strict DDC/CI form for monitors that want it.
    public static func readRequest(_ vcp: UInt8, source: UInt8 = hostAddress, includeSource: Bool = false) -> [UInt8] {
        var bytes: [UInt8] = [0x82, 0x01, vcp]
        bytes.append(checksum(bytes, seed: includeSource ? displayAddress ^ source : displayAddress))
        return bytes
    }

    public static func checksum(_ bytes: [UInt8], seed: UInt8) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Bytes in a Get VCP Feature reply.
    public static let replyLength = 11

    public enum Reply: Equatable, Sendable {
        case value(current: UInt16, maximum: UInt16)
        /// The monitor understood the request but doesn't have this control.
        case unsupported
        /// A DDC/CI null message (`6E 80 BE`): the monitor is there and heard us, but won't report the value.
        /// Many monitors answer every read this way and still obey writes.
        case null
        /// Garbage, a reply to another request, or nothing: worth retrying.
        case invalid
    }

    /// Parses `[0x6E, 0x88, 0x02, result, vcp, type, maxHigh, maxLow, curHigh, curLow, checksum]`.
    /// The checksum is computed as if the host sat at 0x50.
    public static func parseReply(_ bytes: [UInt8], vcp: UInt8) -> Reply {
        if bytes.count >= 3, bytes[1] == 0x80, checksum([bytes[0], bytes[1]], seed: 0x50) == bytes[2] { return .null }
        guard bytes.count >= replyLength else { return .invalid }
        let reply = Array(bytes.prefix(replyLength))
        guard checksum(Array(reply[0..<10]), seed: 0x50) == reply[10],
            reply[2] == 0x02, reply[4] == vcp
        else { return .invalid }
        guard reply[3] == 0x00 else { return .unsupported }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return .value(current: current, maximum: maximum)
    }
}

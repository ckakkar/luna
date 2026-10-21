/// A monitor input and the DDC value that selects it.
public struct InputSource: Identifiable, Hashable, Sendable {
    public var name: String
    public var code: UInt16
    public var symbol: String
    public var id: UInt16 { code }

    /// The standard MCCS input codes (VCP 0x60).
    public static let standard: [InputSource] = [
        InputSource(name: "DisplayPort 1", code: 0x0F, symbol: "rectangle.connected.to.line.below"),
        InputSource(name: "DisplayPort 2", code: 0x10, symbol: "rectangle.connected.to.line.below"),
        InputSource(name: "HDMI 1", code: 0x11, symbol: "cable.connector.horizontal"),
        InputSource(name: "HDMI 2", code: 0x12, symbol: "cable.connector.horizontal"),
        InputSource(name: "HDMI 3", code: 0x13, symbol: "cable.connector.horizontal"),
        InputSource(name: "HDMI 4", code: 0x14, symbol: "cable.connector.horizontal"),
        InputSource(name: "USB-C", code: 0x1B, symbol: "cable.connector"),
        InputSource(name: "USB-C 2", code: 0x1C, symbol: "cable.connector"),
        InputSource(name: "Thunderbolt", code: 0x19, symbol: "bolt.horizontal"),
    ]

    /// LG's own codes (VCP 0xF4 from host address 0x50), for LG monitors that ignore the standard ones.
    public static let lg: [InputSource] = [
        InputSource(name: "DisplayPort 1", code: 0xD0, symbol: "rectangle.connected.to.line.below"),
        InputSource(name: "DisplayPort 2", code: 0xD1, symbol: "rectangle.connected.to.line.below"),
        InputSource(name: "HDMI 1", code: 0x90, symbol: "cable.connector.horizontal"),
        InputSource(name: "HDMI 2", code: 0x91, symbol: "cable.connector.horizontal"),
        InputSource(name: "HDMI 3", code: 0x92, symbol: "cable.connector.horizontal"),
        InputSource(name: "HDMI 4", code: 0x93, symbol: "cable.connector.horizontal"),
        InputSource(name: "USB-C", code: 0xD2, symbol: "cable.connector"),
        InputSource(name: "USB-C 2", code: 0xD3, symbol: "cable.connector"),
    ]

    public static func sources(for method: InputMethod) -> [InputSource] {
        method == .lg ? lg : standard
    }

    /// The name of a code a monitor reported (they often set the high byte, so only the low byte counts).
    public static func name(for code: UInt16) -> String? {
        standard.first { $0.code == code & 0xFF }?.name
    }
}

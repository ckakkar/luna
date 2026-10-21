import CoreGraphics

/// A made-up display for `--preview`: the panel and settings with any mix of displays, no hardware touched.
public struct PreviewDisplay: Sendable {
    public var name: String
    public var kind: DisplayKind
    public var brightness: Double
    public var volume: Double?
    public var input: UInt16?
    public var edrHeadroom: Double
    public var xdr: Bool

    public init(
        name: String, kind: DisplayKind, brightness: Double, volume: Double? = nil, input: UInt16? = nil,
        edrHeadroom: Double = 1, xdr: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.brightness = brightness
        self.volume = volume
        self.input = input
        self.edrHeadroom = edrHeadroom
        self.xdr = xdr
    }

    public static let samples: [PreviewDisplay] = [
        PreviewDisplay(name: "Built-in Retina Display", kind: .builtin, brightness: 0.62, edrHeadroom: 16, xdr: false),
        PreviewDisplay(name: "LG Monitor", kind: .external, brightness: 0.72, volume: 0.35, input: 0x0F),
        PreviewDisplay(name: "Pro Display XDR", kind: .apple, brightness: 1, edrHeadroom: 6, xdr: true),
    ]

    @MainActor
    func makeDisplay(index: Int, app: AppSettings, store: DisplayStore) -> Display {
        let id = CGDirectDisplayID(1000 + index)
        let display = Display(
            id: id, uuid: "preview-\(name)", name: name, kind: kind, identity: DisplayIdentity(name: name),
            control: .preview, app: app, store: store)
        display.xdr = xdr
        display.edrHeadroom = edrHeadroom
        display.level = xdr ? Level(brightness: 1, boost: 0.55) : Level(brightness: brightness)
        if let volume {
            display.hasVolume = true
            display.hasMute = true
            display.volume = volume
        }
        if kind == .external {
            display.hasContrast = true
            display.hasInput = true
            display.input = input
        }
        return display
    }
}

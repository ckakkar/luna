import Foundation

/// What CoreGraphics and CoreDisplay know about a connected display.
public struct DisplayIdentity: Sendable, Equatable {
    public var vendor: Int?
    public var product: Int?
    public var serial: Int?
    public var week: Int?
    public var year: Int?
    /// Image size in millimetres.
    public var width: Int?
    public var height: Int?
    public var name: String?
    /// The IOService path of the display's framebuffer.
    public var ioLocation: String?

    public init(
        vendor: Int? = nil, product: Int? = nil, serial: Int? = nil, week: Int? = nil, year: Int? = nil,
        width: Int? = nil, height: Int? = nil, name: String? = nil, ioLocation: String? = nil
    ) {
        self.vendor = vendor
        self.product = product
        self.serial = serial
        self.week = week
        self.year = year
        self.width = width
        self.height = height
        self.name = name
        self.ioLocation = ioLocation
    }

    /// Reads CoreDisplay's info dictionary (keys as in IOGraphicsTypes.h).
    public init(info: [String: Any]) {
        func int(_ key: String) -> Int? { (info[key] as? NSNumber)?.intValue }
        vendor = int("DisplayVendorID")
        product = int("DisplayProductID")
        serial = int("DisplaySerialNumber")
        week = int("DisplayWeekManufacture")
        year = int("DisplayYearManufacture")
        width = int("DisplayHorizontalImageSize")
        height = int("DisplayVerticalImageSize")
        ioLocation = info["IODisplayLocation"] as? String
        if let names = info["DisplayProductName"] as? [String: String] {
            name = names["en_US"] ?? names.values.sorted().first
        }
    }
}

/// An Apple Silicon framebuffer (AppleCLCD2) that has a DDC-capable AV service.
public struct FramebufferIdentity: Sendable, Equatable {
    /// "EDID UUID", e.g. `1E6D0000-0000-0000-2E1F-0104B53C2278`: vendor, product (byte-swapped), week and
    /// year since 1990, and image size in cm, at fixed offsets.
    public var edidUUID: String
    public var ioLocation: String?
    public var productName: String?
    public var serial: Int?

    public init(edidUUID: String, ioLocation: String? = nil, productName: String? = nil, serial: Int? = nil) {
        self.edidUUID = edidUUID
        self.ioLocation = ioLocation
        self.productName = productName
        self.serial = serial
    }
}

/// Pairs displays with framebuffers, the way MonitorControl does: score every pair on what agrees, then
/// assign greedily from the best score down.
public enum DisplayMatching {
    public static func score(_ display: DisplayIdentity, _ framebuffer: FramebufferIdentity) -> Int {
        let uuid = Array(framebuffer.edidUUID.uppercased())
        func segment(_ offset: Int, _ text: String) -> Int {
            guard offset + text.count <= uuid.count else { return 0 }
            return String(uuid[offset..<offset + text.count]) == text ? 1 : 0
        }
        func hex(_ a: Int, _ b: Int) -> String { String(format: "%02X%02X", a & 0xFF, b & 0xFF) }

        var score = 0
        if let vendor = display.vendor { score += segment(0, String(format: "%04X", vendor & 0xFFFF)) }
        if let product = display.product { score += segment(4, hex(product, product >> 8)) }
        if let week = display.week, let year = display.year, year >= 1990 {
            score += segment(19, hex(week, year - 1990))
        }
        if let width = display.width, let height = display.height, width > 0, height > 0 {
            score += segment(30, hex(Int((Double(width) / 10).rounded()), Int((Double(height) / 10).rounded())))
        }
        if let location = display.ioLocation, location == framebuffer.ioLocation { score += 10 }
        if let name = display.name, let other = framebuffer.productName,
            name.caseInsensitiveCompare(other) == .orderedSame
        {
            score += 1
        }
        if let serial = display.serial, serial != 0, serial == framebuffer.serial { score += 1 }
        return score
    }

    /// Returns framebuffer indices keyed by display ID. A pair that agrees on nothing is only used when it's
    /// the one display and the one framebuffer left.
    public static func assign(
        displays: [(id: UInt32, identity: DisplayIdentity)], framebuffers: [FramebufferIdentity]
    ) -> [UInt32: Int] {
        var pairs: [(display: UInt32, framebuffer: Int, score: Int)] = []
        for display in displays {
            for (index, framebuffer) in framebuffers.enumerated() {
                pairs.append((display.id, index, score(display.identity, framebuffer)))
            }
        }
        pairs.sort { $0.score != $1.score ? $0.score > $1.score : $0.display < $1.display }

        var result: [UInt32: Int] = [:]
        var used = Set<Int>()
        for pair in pairs where result[pair.display] == nil && !used.contains(pair.framebuffer) {
            if pair.score == 0 && !(displays.count == 1 && framebuffers.count == 1) { continue }
            result[pair.display] = pair.framebuffer
            used.insert(pair.framebuffer)
        }
        return result
    }
}

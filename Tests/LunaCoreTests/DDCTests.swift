import Testing

@testable import LunaCore

@Suite struct DDCPacketTests {
    @Test func setBrightnessPacket() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        #expect(DDCPacket.write(VCP.brightness, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test func setValueAboveOneByte() {
        let packet = DDCPacket.write(VCP.volume, value: 0x0123)
        #expect(packet[3] == 0x01 && packet[4] == 0x23)
        #expect(DDCPacket.checksum(Array(packet.dropLast()), seed: 0x6E ^ 0x51) == packet.last)
    }

    @Test func lgSourceAddressChangesChecksum() {
        let standard = DDCPacket.write(VCP.lgInputSource, value: 0xD0)
        let lg = DDCPacket.write(VCP.lgInputSource, value: 0xD0, source: 0x50)
        #expect(standard.dropLast() == lg.dropLast())
        #expect(standard.last! ^ lg.last! == 0x51 ^ 0x50)
    }

    @Test func readRequest() {
        #expect(DDCPacket.readRequest(VCP.brightness) == [0x82, 0x01, 0x10, 0xFD])
        #expect(DDCPacket.readRequest(VCP.brightness, includeSource: true) == [0x82, 0x01, 0x10, 0xFD ^ 0x51])
    }

    static func reply(vcp: UInt8, result: UInt8 = 0, current: UInt16, maximum: UInt16) -> [UInt8] {
        var bytes: [UInt8] = [
            0x6E, 0x88, 0x02, result, vcp, 0x00, UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8),
            UInt8(current & 0xFF),
        ]
        bytes.append(DDCPacket.checksum(bytes, seed: 0x50))
        return bytes
    }

    @Test func parsesReply() {
        let bytes = Self.reply(vcp: VCP.brightness, current: 50, maximum: 100)
        #expect(DDCPacket.parseReply(bytes, vcp: VCP.brightness) == .value(current: 50, maximum: 100))
    }

    @Test func parsesTwoByteValues() {
        let bytes = Self.reply(vcp: VCP.volume, current: 300, maximum: 0x0400)
        #expect(DDCPacket.parseReply(bytes, vcp: VCP.volume) == .value(current: 300, maximum: 1024))
    }

    @Test func rejectsBadReplies() {
        var corrupted = Self.reply(vcp: VCP.brightness, current: 50, maximum: 100)
        corrupted[9] ^= 0x01
        #expect(DDCPacket.parseReply(corrupted, vcp: VCP.brightness) == .invalid)
        #expect(
            DDCPacket.parseReply(Self.reply(vcp: VCP.contrast, current: 1, maximum: 100), vcp: VCP.brightness)
                == .invalid)
        #expect(DDCPacket.parseReply([0x6E, 0x88, 0x02], vcp: VCP.brightness) == .invalid)
        #expect(DDCPacket.parseReply([UInt8](repeating: 0, count: 11), vcp: VCP.brightness) == .invalid)
    }

    @Test func nullMessage() {
        // What many LG monitors answer to every read.
        #expect(
            DDCPacket.parseReply(
                [0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE, 0x6E, 0x80], vcp: VCP.brightness) == .null)
        #expect(DDCPacket.parseReply([0x6E, 0x80, 0xBF], vcp: VCP.brightness) == .invalid)
    }

    @Test func unsupportedControl() {
        let bytes = Self.reply(vcp: VCP.volume, result: 0x01, current: 0, maximum: 0)
        #expect(DDCPacket.parseReply(bytes, vcp: VCP.volume) == .unsupported)
    }
}

@Suite struct DisplayMatchingTests {
    // An LG 27" made in week 46 of 2021: 600 × 340 mm.
    let lg = DisplayIdentity(
        vendor: 0x1E6D, product: 0x5B71, serial: 0, week: 46, year: 2021, width: 600, height: 340, name: "LG Monitor",
        ioLocation: "IOService:/AppleARMPE/arm-io/dispext0/AppleCLCD2")
    let dell = DisplayIdentity(
        vendor: 0x10AC, product: 0xA0C4, week: 10, year: 2019, width: 597, height: 336, name: "DELL U2720Q")

    let lgFramebuffer = FramebufferIdentity(
        edidUUID: "1E6D715B-0000-0000-2E1F-0104B53C2278",
        ioLocation: "IOService:/AppleARMPE/arm-io/dispext0/AppleCLCD2",
        productName: "LG Monitor")
    let dellFramebuffer = FramebufferIdentity(
        edidUUID: "10ACC4A0-0000-0000-0A1D-0104B53C2278", productName: "DELL U2720Q")

    @Test func scoresEveryAgreement() {
        // vendor, product, week/year, size, location (+10), name
        #expect(DisplayMatching.score(lg, lgFramebuffer) == 15)
        #expect(DisplayMatching.score(dell, dellFramebuffer) == 5)
        // Two 27" panels share only their size.
        #expect(DisplayMatching.score(lg, dellFramebuffer) == 1)
    }

    @Test func assignsEachDisplayItsOwnFramebuffer() {
        let result = DisplayMatching.assign(
            displays: [(2, dell), (1, lg)], framebuffers: [lgFramebuffer, dellFramebuffer])
        #expect(result == [1: 0, 2: 1])
    }

    @Test func pairsTheOnlyDisplayWithTheOnlyFramebuffer() {
        let unknown = DisplayIdentity(name: "Monitor")
        #expect(DisplayMatching.assign(displays: [(5, unknown)], framebuffers: [dellFramebuffer]) == [5: 0])
    }

    @Test func leavesUnmatchedDisplaysWithoutDDC() {
        let unknown = DisplayIdentity(name: "Sidecar")
        let result = DisplayMatching.assign(displays: [(1, lg), (9, unknown)], framebuffers: [lgFramebuffer])
        #expect(result == [1: 0])
    }

    @Test func readsCoreDisplayInfo() {
        let info: [String: Any] = [
            "DisplayVendorID": 0x1E6D, "DisplayProductID": 0x5B71, "DisplayYearManufacture": 2021,
            "DisplayProductName": ["en_US": "LG Monitor"], "IODisplayLocation": "IOService:/x",
        ]
        let identity = DisplayIdentity(info: info)
        #expect(identity.vendor == 0x1E6D && identity.product == 0x5B71 && identity.year == 2021)
        #expect(identity.name == "LG Monitor" && identity.ioLocation == "IOService:/x")
    }
}

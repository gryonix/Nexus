import XCTest

@testable import gryonixNexusCore

final class WakeOnLANTests: XCTestCase {
    private let mac = "aa:bb:cc:dd:ee:ff"

    // MARK: - The address

    func testEveryUsualSpellingOfAMACIsTheSameSixBytes() {
        let expected: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        for spelling in ["aa:bb:cc:dd:ee:ff", "AA-BB-CC-DD-EE-FF",
                         "aabb.ccdd.eeff", "AABBCCDDEEFF"] {
            XCTAssertEqual(WakeOnLAN.macBytes(spelling), expected, spelling)
        }
    }

    func testAHalfTypedAddressIsNotAMAC() {
        for text in ["", "aa:bb", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00",
                     "zz:bb:cc:dd:ee:ff", "aabbccddeef"] {
            XCTAssertNil(WakeOnLAN.macBytes(text), text)
        }
    }

    func testAStoredAddressIsWrittenOneWay() {
        XCTAssertEqual(WakeOnLAN.normalised("AA-BB-CC-DD-EE-FF"), mac)
        XCTAssertEqual(WakeOnLAN.normalised("aabbccddeeff"), mac)
        XCTAssertNil(WakeOnLAN.normalised("not a mac"))
    }

    // MARK: - The packet

    func testTheMagicPacketIsSixOnesAndSixteenCopies() throws {
        let packet = try XCTUnwrap(WakeOnLAN.magicPacket(mac: mac))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), Array(repeating: 0xFF, count: 6))
        let address: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        for copy in 0..<16 {
            let start = 6 + copy * 6
            XCTAssertEqual(Array(packet[start..<(start + 6)]), address,
                           "copy \(copy) of the address is not the address")
        }
    }

    func testNoPacketForSomethingThatIsNotAnAddress() {
        XCTAssertNil(WakeOnLAN.magicPacket(mac: "aa:bb:cc"))
    }

    // MARK: - Where it goes

    func testTheBroadcastAddressIsTheSubnetsOwn() {
        XCTAssertEqual(WakeOnLAN.broadcastAddress(for: "192.168.1.40"), "192.168.1.255")
        XCTAssertEqual(WakeOnLAN.broadcastAddress(for: "10.0.0.2"), "10.0.0.255")
    }

    func testAHostnameHasNoBroadcastAddress() {
        for host in ["server.example.com", "localhost", "192.168.1", "192.168.1.999", ""] {
            XCTAssertNil(WakeOnLAN.broadcastAddress(for: host), host)
        }
    }

    // MARK: - The peer's command

    /// What a server on that network runs
    func testThePeerCommandWritesThePacketIntoTheBroadcastAddress() throws {
        let command = try XCTUnwrap(WakeOnLAN.command(mac: mac, broadcast: "192.168.1.255"))
        XCTAssertTrue(command.hasPrefix("python3 -c 'import socket"), command)
        XCTAssertTrue(command.contains("SO_BROADCAST"), "a broadcast needs the option, or Linux refuses it")
        XCTAssertTrue(command.contains("|| bash -c 'printf \""), command)
        XCTAssertTrue(command.hasSuffix("> /dev/udp/192.168.1.255/9'"), command)
        let escapes = command.components(separatedBy: "\\x").count - 1
        XCTAssertEqual(escapes, 102)
        XCTAssertTrue(command.contains("bytes.fromhex(\"" + String(repeating: "ff", count: 6)))
        XCTAssertTrue(command.contains(String(repeating: "\\xff", count: 6)),
                      "the packet does not start with the six 0xFF bytes")
    }

    func testNoPeerCommandWithoutBothHalves() {
        XCTAssertNil(WakeOnLAN.command(mac: "aa:bb", broadcast: "192.168.1.255"))
        XCTAssertNil(WakeOnLAN.command(mac: mac, broadcast: "server.example.com"))
    }

    func testReadGivesTheMACAndTheBroadcast() {
        let read = WakeOnLAN.parseRead("E0:3F:49:AE:F3:D5\n192.168.178.255\n")
        XCTAssertEqual(read?.mac, "e0:3f:49:ae:f3:d5")
        XCTAssertEqual(read?.broadcast, "192.168.178.255")
        XCTAssertNil(WakeOnLAN.parseRead("e0:3f:49:ae:f3:d5\n")?.broadcast)
        XCTAssertNil(WakeOnLAN.parseRead("no device\n"))
    }

    func testThereIsAlwaysSomewhereToSend() {
        XCTAssertEqual(WakeOnLAN.broadcast(stored: "10.0.0.255", host: "draco.local", resolved: nil), "10.0.0.255")
        XCTAssertEqual(WakeOnLAN.broadcast(stored: nil, host: "192.168.1.20", resolved: nil), "192.168.1.255")
        XCTAssertEqual(WakeOnLAN.broadcast(stored: nil, host: "draco.local", resolved: "192.168.178.40"), "192.168.178.255")
        XCTAssertEqual(WakeOnLAN.broadcast(stored: nil, host: "draco.local", resolved: nil), "255.255.255.255")
    }
}

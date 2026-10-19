import XCTest
@testable import VPNProfile

final class WireGuardQuickConfigTests: XCTestCase {
    private let valid = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32
    DNS = 10.9.0.1

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    """

    func testParsesEndpointAndName() throws {
        let config = try WireGuardQuickConfig(parsing: valid)
        XCTAssertEqual(config.endpoint, "vpn.example.com:51820")
        XCTAssertEqual(config.name, "vpn.example.com")
    }

    /// The text is what the tunnel app actually reads
    func testTextIsKeptVerbatimApartFromSurroundingWhitespace() throws {
        let config = try WireGuardQuickConfig(parsing: "\n\n" + valid + "\n  ")
        XCTAssertEqual(config.rawText, valid)
    }

    func testRepeatedAddressAndAllowedIPsLinesAreAllRead() throws {
        let text = valid
            .replacingOccurrences(of: "Address = 10.9.0.4/32", with: "Address = 10.9.0.4/32\nAddress = fd09::4/128")
            .replacingOccurrences(of: "AllowedIPs = 0.0.0.0/0", with: "AllowedIPs = 0.0.0.0/0\nAllowedIPs = ::/0")
        let config = try WireGuardQuickConfig(parsing: text)
        XCTAssertEqual(config.addresses, ["10.9.0.4/32", "fd09::4/128"])
        XCTAssertEqual(config.allowedIPs, ["0.0.0.0/0", "::/0"])
    }

    func testAConfigWithTwoPeersIsRefused() {
        let text = valid + "\n\n[Peer]\nPublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=\nEndpoint = b.example.com:1\n"
        XCTAssertThrowsError(try WireGuardQuickConfig(parsing: text)) {
            XCTAssertEqual($0 as? WireGuardQuickConfig.ParseError, .severalPeers)
        }
    }

    func testIPv6EndpointYieldsTheAddressWithoutBrackets() throws {
        let config = try WireGuardQuickConfig(
            parsing: valid.replacingOccurrences(of: "vpn.example.com:51820",
                                                with: "[2001:db8::1]:51820"))
        XCTAssertEqual(config.endpoint, "[2001:db8::1]:51820")
        XCTAssertEqual(config.name, "2001:db8::1")
    }

    func testSectionHeadersAreMatchedCaseInsensitively() throws {
        let shouted = valid
            .replacingOccurrences(of: "[Interface]", with: "[INTERFACE]")
            .replacingOccurrences(of: "[Peer]", with: "[peer]")
        XCTAssertNoThrow(try WireGuardQuickConfig(parsing: shouted))
    }

    func testKeysAreMatchedCaseInsensitively() throws {
        let config = try WireGuardQuickConfig(
            parsing: valid.replacingOccurrences(of: "Endpoint =", with: "endpoint ="))
        XCTAssertEqual(config.endpoint, "vpn.example.com:51820")
    }

    func testTheInterfaceKeyAndThePresharedKeyAreReadOut() throws {
        let config = try WireGuardQuickConfig(parsing: valid.replacingOccurrences(
            of: "[Peer]",
            with: "[Peer]\nPresharedKey = 4c3JZoJ8LO3yQCkjuXcbnMXctA7vlSFCDgTbLbUsvFI="))
        XCTAssertEqual(config.interfacePrivateKey,
                       "mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=")
        XCTAssertEqual(config.peerPresharedKey,
                       "4c3JZoJ8LO3yQCkjuXcbnMXctA7vlSFCDgTbLbUsvFI=")
    }

    func testAPeerWithNoPresharedKeyAnswersNilRatherThanEmpty() throws {
        let config = try WireGuardQuickConfig(parsing: valid)
        XCTAssertNil(config.peerPresharedKey)
        XCTAssertNotNil(config.interfacePrivateKey,
                        "the interface key is not optional in anything the panel writes")
    }

    /// The keys are read from their OWN sections
    func testEachKeyIsReadFromItsOwnSection() throws {
        let swapped = """
        [Interface]
        Address = 10.9.0.4/32
        PresharedKey = 4c3JZoJ8LO3yQCkjuXcbnMXctA7vlSFCDgTbLbUsvFI=

        [Peer]
        PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
        PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
        Endpoint = vpn.example.com:51820
        """
        let config = try WireGuardQuickConfig(parsing: swapped)
        XCTAssertNil(config.interfacePrivateKey, "a peer's PrivateKey is not the interface's")
        XCTAssertNil(config.peerPresharedKey, "an interface's PresharedKey is not the peer's")
    }

    // MARK: - Refusals

    func testRefusesTextThatIsNotAWireGuardConfig() {
        assert(parsing: "ss://YWVzOnBhc3N3b3Jk@example.com:8388", throws: .missingInterface)
        assert(parsing: "[Interface]\nPrivateKey = x", throws: .missingPeer)
        assert(parsing: "[Interface]\nPrivateKey = x\n[Peer]\nPublicKey = y",
               throws: .missingEndpoint)
    }

    func testRefusesAnEmptyEndpoint() {
        assert(parsing: "[Interface]\nPrivateKey = x\n[Peer]\nEndpoint =   ",
               throws: .missingEndpoint)
    }

    private func assert(parsing text: String,
                        throws expected: WireGuardQuickConfig.ParseError,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try WireGuardQuickConfig(parsing: text), file: file, line: line) {
            XCTAssertEqual($0 as? WireGuardQuickConfig.ParseError, expected, file: file, line: line)
        }
    }
}

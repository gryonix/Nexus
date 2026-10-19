#if canImport(WireGuardKit)
import XCTest
import VPNProfile
import WireGuardKit

/// The mapping from the panel's wg-quick onto the adapter's types
final class TunnelConfigurationBuilderTests: XCTestCase {
    /// The first configuration the golden carries for the named protocol
    private func golden(_ protocolName: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        // .../Apple/TunnelExtensionTests/<this file> → `Apple/`.
        for _ in 0..<2 { url.deleteLastPathComponent() }
        let file = url.appendingPathComponent(
            "Packages/gryonixNexus/Tests/VPNTunnelTests/Resources/panel-vpn-configs.json")
        guard let data = try? Data(contentsOf: file) else {
            XCTFail("no panel golden at \(file.path)")
            throw CocoaError(.fileNoSuchFile)
        }
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cases = document?["cases"] as? [[String: Any]] ?? []
        guard let text = cases.first(where: { $0["protocol"] as? String == protocolName })?["text"]
                as? String else {
            XCTFail("the golden carries no \(protocolName) configuration")
            throw CocoaError(.fileNoSuchFile)
        }
        return text
    }

    // MARK: - The nine values

    func testEachObfuscationValueReachesItsOwnField() {
        let values = [("Jc", "1"), ("Jmin", "2"), ("Jmax", "3"), ("S1", "4"), ("S2", "5"),
                      ("H1", "11"), ("H2", "22"), ("H3", "33"), ("H4", "44")]
            .map { (key: $0.0, value: $0.1) }
        var interface = InterfaceConfiguration(privateKey: PrivateKey())
        TunnelConfigurationBuilder.applyObfuscation(values, to: &interface)

        XCTAssertEqual(interface.junkPacketCount, 1, "Jc is the junk packet COUNT")
        XCTAssertEqual(interface.junkPacketMinSize, 2)
        XCTAssertEqual(interface.junkPacketMaxSize, 3)
        XCTAssertEqual(interface.initPacketJunkSize, 4, "S1 sizes the INIT packet's junk")
        XCTAssertEqual(interface.responsePacketJunkSize, 5, "S2 sizes the RESPONSE packet's junk")
        XCTAssertEqual(interface.initPacketMagicHeader, "11", "H1 heads the INIT packet")
        XCTAssertEqual(interface.responsePacketMagicHeader, "22", "H2 heads the RESPONSE packet")
        XCTAssertEqual(interface.underloadPacketMagicHeader, "33", "H3 heads the UNDERLOAD packet")
        XCTAssertEqual(interface.transportPacketMagicHeader, "44", "H4 heads the TRANSPORT packet")
    }

    func testAKeyFromANewerPanelIsIgnoredRatherThanGuessedAt() {
        var interface = InterfaceConfiguration(privateKey: PrivateKey())
        TunnelConfigurationBuilder.applyObfuscation([(key: "S9", value: "7")], to: &interface)
        XCTAssertNil(interface.initPacketJunkSize)
        XCTAssertNil(interface.responsePacketJunkSize)
    }

    // MARK: - The captured AmneziaWG configuration

    func testTheCapturedAmneziaConfigBecomesATunnelConfiguration() throws {
        let parsed = try WireGuardQuickConfig(parsing: golden("amneziawg"))
        let configuration = try TunnelConfigurationBuilder.make(from: parsed, name: "test")

        XCTAssertEqual(configuration.interface.addresses.map(\.stringRepresentation),
                       ["10.10.0.2/24"])
        XCTAssertEqual(configuration.interface.dns.map(\.stringRepresentation), ["1.1.1.1"])
        XCTAssertEqual(configuration.interface.mtu, 1280)
        XCTAssertEqual(configuration.interface.junkPacketCount, 4)
        XCTAssertEqual(configuration.interface.junkPacketMaxSize, 70)
        XCTAssertEqual(configuration.interface.responsePacketJunkSize, 100)
        XCTAssertEqual(configuration.interface.initPacketMagicHeader, "1234567891")
        XCTAssertEqual(configuration.interface.responsePacketMagicHeader, "1234567892")
        XCTAssertEqual(configuration.interface.underloadPacketMagicHeader, "1234567893")
        XCTAssertEqual(configuration.interface.transportPacketMagicHeader, "1234567894")

        XCTAssertEqual(configuration.peers.count, 1)
        let peer = try XCTUnwrap(configuration.peers.first)
        XCTAssertNotNil(peer.preSharedKey, "the panel gives AmneziaWG a PresharedKey")
        XCTAssertEqual(peer.endpoint?.stringRepresentation, "vpn.example.com:51830")
        XCTAssertEqual(peer.allowedIPs.map(\.stringRepresentation), ["0.0.0.0/0"])
        XCTAssertEqual(peer.persistentKeepAlive, "25")
    }

    func testTheCapturedPlainWireGuardConfigCarriesNoObfuscation() throws {
        let parsed = try WireGuardQuickConfig(parsing: golden("wireguard"))
        let configuration = try TunnelConfigurationBuilder.make(from: parsed, name: "test")
        XCTAssertNil(configuration.interface.junkPacketCount)
        XCTAssertNil(configuration.interface.initPacketMagicHeader)
        XCTAssertNil(configuration.interface.transportPacketMagicHeader)
        XCTAssertNil(configuration.peers.first?.preSharedKey,
                     "plain WireGuard from this panel has no PresharedKey")
        XCTAssertEqual(configuration.peers.first?.endpoint?.stringRepresentation,
                       "vpn.example.com:51820")
    }

    // MARK: - Refusals

    func testAConfigWithNoPrivateKeyIsRefusedBeforeTheAdapterSeesIt() throws {
        let text = """
            [Interface]
            Address = 10.0.0.2/32

            [Peer]
            PublicKey = uPObfH5LCq0h2smJirq5ulNa1ZSjTM/LGqO9CtxQXdw=
            Endpoint = 203.0.113.10:51820
            AllowedIPs = 0.0.0.0/0
            """
        let parsed = try WireGuardQuickConfig(parsing: text)
        XCTAssertThrowsError(try TunnelConfigurationBuilder.make(from: parsed, name: "x")) { error in
            guard let failure = error as? TunnelConfigurationBuilder.Failure,
                  case .missingPrivateKey = failure else {
                return XCTFail("expected missingPrivateKey, got \(error)")
            }
        }
    }

    func testAKeyOfTheWrongLengthIsRefusedWithItsFieldNamed() throws {
        let text = """
            [Interface]
            PrivateKey = dG9vLXNob3J0

            [Peer]
            PublicKey = uPObfH5LCq0h2smJirq5ulNa1ZSjTM/LGqO9CtxQXdw=
            Endpoint = 203.0.113.10:51820
            AllowedIPs = 0.0.0.0/0
            """
        let parsed = try WireGuardQuickConfig(parsing: text)
        XCTAssertThrowsError(try TunnelConfigurationBuilder.make(from: parsed, name: "x")) { error in
            guard let failure = error as? TunnelConfigurationBuilder.Failure,
                  case .badKey(let name) = failure else {
                return XCTFail("expected badKey, got \(error)")
            }
            XCTAssertEqual(name, "PrivateKey")
        }
    }
}
#endif

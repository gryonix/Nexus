import ServiceCatalog
import VPNProfile
import XCTest
@testable import VPNTunnel

final class TunnelProfileRefusalTests: XCTestCase {
    /// What the panel prints, minus nothing
    private let sound = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32
    DNS = 10.9.0.1
    MTU = 1280

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    """

    private func build(_ text: String,
                       protocolID: ServiceID = .wireguardVPN) throws
        -> TunnelProfileBuilder.Built {
        try TunnelProfileBuilder.build(text: text, protocolID: protocolID,
                                       serverID: UUID(), serverName: "Home",
                                       deviceID: "device-1", deviceName: "iPhone")
    }

    private func assertRefused(_ text: String,
                               _ expected: WireGuardQuickConfig.ParseError,
                               _ message: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertThrowsError(try build(text), message, file: file, line: line) { error in
            XCTAssertEqual(error as? TunnelProfileBuilder.Failure,
                           .unreadable(expected), message, file: file, line: line)
        }
    }

    // MARK: - The file stops early

    func testATransferCutBeforeThePeerIsRefused() {
        let cut = sound.components(separatedBy: "[Peer]")[0]
        assertRefused(cut, .missingPeer,
                      "a configuration with no server end is not a tunnel")
    }

    func testATransferCutBeforeTheEndpointIsRefused() {
        let cut = """
        [Interface]
        PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
        Address = 10.9.0.4/32

        [Peer]
        PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
        """
        assertRefused(cut, .missingEndpoint,
                      "a peer with no address is not somewhere this can dial")
    }

    func testATransferCutInsideTheEndpointIsNotCaught() throws {
        let cut = sound.components(separatedBy: "Endpoint = ")[0] + "Endpoint = vpn.exa"
        let built = try build(cut)
        XCTAssertEqual(built.profile.endpoint, "vpn.exa",
                       "half an endpoint is carried whole, because nothing here can tell")
    }

    // MARK: - The file is complete and says something unexpected

    func testAnUnusualAllowedIPsIsCarriedAndNeverWidened() throws {
        let split = sound.replacingOccurrences(of: "AllowedIPs = 0.0.0.0/0",
                                               with: "AllowedIPs = 192.168.77.0/24")
        let built = try build(split)
        XCTAssertEqual(built.profile.allowedIPs, ["192.168.77.0/24"],
                       "the routes the config asked for are the routes it gets")
        XCTAssertFalse(built.profile.allowedIPs.contains("0.0.0.0/0"),
                       "a split tunnel must never be widened into a full one")
    }

    func testAFullTunnelKeepsItsFullRoutes() throws {
        XCTAssertEqual(try build(sound).profile.allowedIPs, ["0.0.0.0/0"])
    }

    // MARK: - AmneziaWG, half-dressed

    func testAPartlyObfuscatedConfigurationIsAcceptedAsObfuscated() throws {
        let partial = """
        [Interface]
        PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
        Address = 10.10.0.4/32
        MTU = 1280
        Jc = 4
        Jmin = 40
        Jmax = 70
        S1 = 78
        S2 = 61

        [Peer]
        PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
        Endpoint = vpn.example.com:51821
        AllowedIPs = 0.0.0.0/0
        """
        let built = try build(partial, protocolID: .amneziaWG)
        XCTAssertTrue(built.profile.isObfuscated,
                      "five values present still reads as obfuscated today")

        let config = try WireGuardQuickConfig(parsing: partial)
        XCTAssertEqual(config.obfuscation.map(\.key), ["Jc", "Jmin", "Jmax", "S1", "S2"],
                       "and exactly the five that were there, in the panel's order")
    }

    func testTheSecretIsTheWholeConfigurationAndNotWhatWasParsedBackOut() throws {
        let withPSK = sound.replacingOccurrences(
            of: "Endpoint = vpn.example.com:51820",
            with: "PresharedKey = 4Ck2y0nJLsWuDS0kMPy0GgnkKM2mHRE0N9jVdVMlmDU=\nEndpoint = vpn.example.com:51820")
        let built = try build(withPSK)
        XCTAssertTrue(built.secret.contains("PresharedKey ="),
                      "a line with no field of its own still has to reach the tunnel")
        XCTAssertEqual(built.secret, withPSK.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

import XCTest
@testable import VPNProfile

final class OpenVPNProfileConfigTests: XCTestCase {
    private let text = """
    client
    dev tun
    proto udp
    remote vpn.example.com 1194
    resolv-retry infinite
    nobind
    persist-key
    persist-tun
    remote-cert-tls server
    cipher AES-256-GCM
    verb 3
    <ca>
    -----BEGIN CERTIFICATE-----
    MIIB1jCCAX2gAwIBAgIUAAAA
    -----END CERTIFICATE-----
    </ca>
    <cert>
    -----BEGIN CERTIFICATE-----
    MIIB2jCCAYGgAwIBAgIUBBBB
    -----END CERTIFICATE-----
    </cert>
    <key>
    -----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VwBCIEIAAA
    -----END PRIVATE KEY-----
    </key>
    """

    private func vendor(_ source: String? = nil) throws -> [String: String] {
        try OpenVPNProfileConfig(parsing: source ?? text).vendorConfig
    }

    // MARK: - One key per directive

    func testEachDirectiveBecomesAKeyWithItsArgumentsAsTheValue() throws {
        let vendor = try vendor()
        XCTAssertEqual(vendor["dev"], "tun")
        XCTAssertEqual(vendor["proto"], "udp")
        XCTAssertEqual(vendor["remote"], "vpn.example.com 1194")
        XCTAssertEqual(vendor["remote-cert-tls"], "server")
        XCTAssertEqual(vendor["cipher"], "AES-256-GCM")
        XCTAssertEqual(vendor["verb"], "3")
    }

    func testADirectiveWithNoArgumentsBecomesNOARGS() throws {
        let vendor = try vendor()
        XCTAssertEqual(vendor["client"], "NOARGS")
        XCTAssertEqual(vendor["nobind"], "NOARGS")
        XCTAssertEqual(vendor["persist-key"], "NOARGS")
        XCTAssertEqual(vendor["persist-tun"], "NOARGS")
    }

    func testCommentsAndBlankLinesAreNotDirectives() throws {
        let vendor = try vendor("""
        # exported by the panel
        ; an old-style comment

        client
        remote vpn.example.com 1194
        """)
        XCTAssertNil(vendor["#"])
        XCTAssertNil(vendor[";"])
        XCTAssertEqual(vendor["client"], "NOARGS")
    }

    // MARK: - Inline blocks

    func testAnInlineBlockBecomesOneLineWithEscapedBreaks() throws {
        let vendor = try vendor()
        XCTAssertEqual(vendor["ca"],
                       "-----BEGIN CERTIFICATE-----\\nMIIB1jCCAX2gAwIBAgIUAAAA\\n-----END CERTIFICATE-----")
        XCTAssertFalse(try XCTUnwrap(vendor["key"]).contains("\n"))
    }

    func testTheBlockTagsDoNotBecomeKeys() throws {
        let vendor = try vendor()
        XCTAssertNil(vendor["<ca>"])
        XCTAssertNil(vendor["</ca>"])
    }

    func testCommentLinesInsideABlockAreKeptBecauseTheyArePartOfTheKey() throws {
        let vendor = try vendor("""
        client
        remote vpn.example.com 1194
        key-direction 1
        <tls-auth>
        #
        # 2048 bit OpenVPN static key
        #
        -----BEGIN OpenVPN Static key V1-----
        6acef03f62675b4b1bbd03e53b187727
        -----END OpenVPN Static key V1-----
        </tls-auth>
        """)
        XCTAssertEqual(vendor["tls-auth"],
                       "#\\n# 2048 bit OpenVPN static key\\n#\\n"
                       + "-----BEGIN OpenVPN Static key V1-----\\n"
                       + "6acef03f62675b4b1bbd03e53b187727\\n"
                       + "-----END OpenVPN Static key V1-----")
        XCTAssertEqual(vendor["key-direction"], "1")
    }

    func testABackslashIsEscapedBeforeTheLineBreaksAre() {
        XCTAssertEqual(OpenVPNProfileConfig.escaped("a\\b"), "a\\\\b")
        XCTAssertEqual(OpenVPNProfileConfig.escaped("a\nb"), "a\\nb")
        XCTAssertEqual(OpenVPNProfileConfig.escaped("a\\\nb"), "a\\\\\\nb")
    }

    func testAnUnterminatedBlockIsRefusedRatherThanSwallowingTheRestOfTheFile() {
        XCTAssertThrowsError(try vendor("""
        client
        remote vpn.example.com 1194
        <ca>
        -----BEGIN CERTIFICATE-----
        """)) { error in
            XCTAssertEqual(error as? OpenVPNProfileConfig.ParseError, .unterminatedInlineBlock("ca"))
        }
    }

    // MARK: - Repeated directives

    func testRepeatedDirectivesAreNumberedInFileOrder() throws {
        let vendor = try vendor("""
        client
        remote first.example.com 1194
        remote second.example.com 443 tcp
        remote third.example.com 1195
        """)
        XCTAssertEqual(vendor["remote.1"], "first.example.com 1194")
        XCTAssertEqual(vendor["remote.2"], "second.example.com 443 tcp")
        XCTAssertEqual(vendor["remote.3"], "third.example.com 1195")
        XCTAssertNil(vendor["remote"])
    }

    /// ...and a directive appearing once keeps its plain name
    func testASingleDirectiveIsNotNumbered() throws {
        let vendor = try vendor()
        XCTAssertEqual(vendor["dev"], "tun")
        XCTAssertNil(vendor["dev.1"])
    }

    // MARK: - The keys OpenVPN adds

    func testTheOnDemandMarkerIsAlwaysPresentAndAlwaysZero() throws {
        XCTAssertEqual(try vendor()["vpn-on-demand"], "0")
        XCTAssertEqual(try vendor("""
        client
        remote vpn.example.com 1194
        vpn-on-demand 1
        """)["vpn-on-demand"], "0")
    }

    func testAProfileWithoutCertificatesSaysSoExplicitly() throws {
        XCTAssertEqual(try vendor("""
        client
        remote vpn.example.com 1194
        auth-user-pass
        """)["setenv"], "CLIENT_CERT 0")
    }

    func testAProfileWithCertificatesDoesNotClaimToHaveNone() throws {
        XCTAssertNil(try vendor()["setenv"])
    }

    // MARK: - Refusing what cannot work

    /// A profile with no `remote` has no server to reach
    func testAProfileWithNoRemoteIsRefused() {
        XCTAssertThrowsError(try vendor("client\ndev tun\n")) { error in
            XCTAssertEqual(error as? OpenVPNProfileConfig.ParseError, .noRemote)
        }
    }

    func testSomethingThatIsNotAProfileAtAllIsRefused() {
        XCTAssertThrowsError(try vendor("   \n\n  ")) { error in
            XCTAssertEqual(error as? OpenVPNProfileConfig.ParseError, .noDirectives)
        }
    }

    // MARK: - Where it goes

    func testTheFirstRemoteIsTheEndpoint() throws {
        let config = try OpenVPNProfileConfig(parsing: text)
        XCTAssertEqual(config.remoteEndpoint, "vpn.example.com:1194")
    }

    func testTheFIRSTRemoteWins() throws {
        let config = try OpenVPNProfileConfig(parsing: """
        client
        remote first.example.com 1194
        remote second.example.com 1195
        remote third.example.com 443
        """)
        XCTAssertEqual(config.remoteEndpoint, "first.example.com:1194")
    }

    func testARemoteWithNoPortKeepsTheHostAndInventsNothing() throws {
        let config = try OpenVPNProfileConfig(parsing: "client\nremote vpn.example.com\n")
        XCTAssertEqual(config.remoteEndpoint, "vpn.example.com")
    }

    func testANonsensePortIsDroppedRatherThanCarried() throws {
        XCTAssertEqual(try OpenVPNProfileConfig(parsing: "client\nremote vpn.example.com udp\n")
                        .remoteEndpoint, "vpn.example.com")
        XCTAssertEqual(try OpenVPNProfileConfig(parsing: "client\nremote vpn.example.com 0\n")
                        .remoteEndpoint, "vpn.example.com")
        XCTAssertEqual(try OpenVPNProfileConfig(parsing: "client\nremote vpn.example.com 70000\n")
                        .remoteEndpoint, "vpn.example.com")
    }

    func testAProfileWithNoRemoteIsRefusedByTheParseItself() {
        XCTAssertThrowsError(try OpenVPNProfileConfig(parsing: "client\ndev tun\nproto udp\n")) {
            XCTAssertEqual($0 as? OpenVPNProfileConfig.ParseError, .noRemote)
        }
    }

    func testABareRemoteLineNamesNoEndpointRatherThanNOARGS() throws {
        let config = try OpenVPNProfileConfig(parsing: "client\ndev tun\nremote\n")
        XCTAssertEqual(config.vendorConfig["remote"], "NOARGS",
                       "the payload still records the directive as the format requires")
        XCTAssertNil(config.remoteEndpoint)
    }

    // MARK: - The original

    func testTheOriginalTextIsKept() throws {
        XCTAssertEqual(try OpenVPNProfileConfig(parsing: text).rawText, text)
    }

    /// Windows line endings are a file-transfer artefact, not content
    func testCarriageReturnsDoNotSurviveIntoTheValues() throws {
        let vendor = try vendor("client\r\nremote vpn.example.com 1194\r\ndev tun\r\n")
        XCTAssertEqual(vendor["dev"], "tun")
        XCTAssertEqual(vendor["remote"], "vpn.example.com 1194")
        XCTAssertEqual(vendor["client"], "NOARGS")
    }
}

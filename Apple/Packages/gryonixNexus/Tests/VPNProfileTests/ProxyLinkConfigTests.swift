import XCTest
@testable import VPNProfile

/// The two share links, taken apart
final class ProxyLinkConfigTests: XCTestCase {
    private let shadowsocks =
        "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#iPhone"

    private let vless = "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@vpn.example.com:443"
        + "?encryption=none&security=reality&sni=www.microsoft.com"
        + "&fp=chrome&pbk=xrK4Y_1n7Qk&sid=9a3f&type=tcp&flow=xtls-rprx-vision#iPhone"

    func testASIP002LinkGivesItsEndpointAndCredential() throws {
        let link = try ProxyLinkConfig(parsing: shadowsocks, kind: .shadowsocks)

        XCTAssertEqual(link.host, "vpn.example.com")
        XCTAssertEqual(link.port, 8388)
        XCTAssertEqual(link.endpoint, "vpn.example.com:8388")
        XCTAssertEqual(link.credential, .shadowsocks(method: "aes-256-gcm", password: "secret"))
        XCTAssertEqual(link.label, "iPhone")
    }

    func testTheLegacyFormIsReadRatherThanRefused() throws {
        let legacy = "ss://" + Data("aes-256-gcm:secret@vpn.example.com:8388".utf8)
            .base64EncodedString() + "#iPhone"

        let link = try ProxyLinkConfig(parsing: legacy, kind: .shadowsocks)

        XCTAssertEqual(link.endpoint, "vpn.example.com:8388")
        XCTAssertEqual(link.credential, .shadowsocks(method: "aes-256-gcm", password: "secret"))
    }

    func testAPasswordContainingAColonSurvives() throws {
        let text = "ss://" + Data("chacha20-ietf-poly1305:a:b:c@vpn.example.com:443".utf8)
            .base64EncodedString()

        let link = try ProxyLinkConfig(parsing: text, kind: .shadowsocks)

        XCTAssertEqual(link.credential,
                       .shadowsocks(method: "chacha20-ietf-poly1305", password: "a:b:c"))
    }

    func testAPanelLinkWithAServerAndUserKeyKeepsBothKeys() throws {
        let text = "ss://2022-blake3-aes-256-gcm:aB%2Bc%2FdE%3D:fG%2Bh%2FiJ%3D@vpn.example.com:8388#iPhone"

        let link = try ProxyLinkConfig(parsing: text, kind: .shadowsocks)

        XCTAssertEqual(link.credential,
                       .shadowsocks(method: "2022-blake3-aes-256-gcm", password: "aB+c/dE=:fG+h/iJ="))
        XCTAssertEqual(link.endpoint, "vpn.example.com:8388")
    }

    func testACredentialWrittenInTheClearIsRead() throws {
        let link = try ProxyLinkConfig(parsing: "ss://aes-256-gcm:secret@vpn.example.com:8388#p",
                                       kind: .shadowsocks)

        XCTAssertEqual(link.credential, .shadowsocks(method: "aes-256-gcm", password: "secret"))
        XCTAssertEqual(link.endpoint, "vpn.example.com:8388")
    }

    func testAVLESSLinkGivesItsRealityParameters() throws {
        let link = try ProxyLinkConfig(parsing: vless, kind: .vless)

        XCTAssertEqual(link.endpoint, "vpn.example.com:443")
        XCTAssertEqual(link.credential,
                       .vless(.init(uuid: "3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f",
                                    security: "reality",
                                    sni: "www.microsoft.com",
                                    fingerprint: "chrome",
                                    publicKey: "xrK4Y_1n7Qk",
                                    shortID: "9a3f",
                                    flow: "xtls-rprx-vision",
                                    network: "tcp",
                                    path: "",
                                    host: "",
                                    serviceName: "")))
    }

    func testALabelWithSpacesAndCyrillicSurvivesTheURL() throws {
        let link = try ProxyLinkConfig(parsing: shadowsocks.replacingOccurrences(
            of: "#iPhone", with: "#iPhone Марины"), kind: .shadowsocks)

        XCTAssertEqual(link.label, "iPhone Марины")
        XCTAssertEqual(link.endpoint, "vpn.example.com:8388")
    }

    func testTheLinkIsFoundAmongOtherLines() throws {
        let text = "# gryonixNexus — iPhone\n\n\(shadowsocks)\n"

        XCTAssertEqual(try ProxyLinkConfig(parsing: text, kind: .shadowsocks).port, 8388)
    }

    // MARK: - Refusals

    func testTextThatIsNotALinkOfThisKindIsRefusedByKind() {
        XCTAssertThrowsError(try ProxyLinkConfig(parsing: vless, kind: .shadowsocks)) { error in
            XCTAssertEqual(error as? ProxyLinkConfig.ParseError, .noLink(.shadowsocks))
        }
    }

    func testALinkWithoutAPortIsRefused() {
        XCTAssertThrowsError(
            try ProxyLinkConfig(parsing: "vless://uuid@vpn.example.com#iPhone", kind: .vless)
        ) { error in
            XCTAssertEqual(error as? ProxyLinkConfig.ParseError, .noEndpoint(.vless))
        }
    }

    func testAPortOutsideTheRangeIsRefused() {
        XCTAssertThrowsError(
            try ProxyLinkConfig(parsing: "vless://uuid@vpn.example.com:70000", kind: .vless)
        ) { error in
            XCTAssertEqual(error as? ProxyLinkConfig.ParseError, .noEndpoint(.vless))
        }
    }

    /// Where to go without how to authenticate
    func testALinkWithNoCredentialIsRefused() {
        XCTAssertThrowsError(
            try ProxyLinkConfig(parsing: "ss://vpn.example.com:8388", kind: .shadowsocks)
        ) { error in
            XCTAssertNotNil(error as? ProxyLinkConfig.ParseError)
        }
    }

    func testAShadowsocks2022KeyStoredWithAnExtraEncodingPassStillDecodes() throws {
        let text = "ss://2022-blake3-aes-256-gcm:aB%252Bc%252FdE%253D:fG%252Bh%252FiJ%253D@vpn.example.com:8388#iPhone"
        let config = try ProxyLinkConfig(parsing: text)
        XCTAssertEqual(config.credential,
                       .shadowsocks(method: "2022-blake3-aes-256-gcm", password: "aB+c/dE=:fG+h/iJ="))
    }
}

import XCTest
@testable import VPNProfile

final class XrayConfigurationTests: XCTestCase {
    private let shadowsocks =
        "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#iPhone"

    private let reality = "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@vpn.example.com:443"
        + "?encryption=none&security=reality&sni=www.microsoft.com"
        + "&fp=chrome&pbk=xrK4Y_1n7Qk&sid=9a3f&type=tcp&flow=xtls-rprx-vision#iPhone"

    private let access = LocalProxyAccess(port: 40123, username: "session-user", password: "session-pass")

    private func outbound(_ text: String, _ kind: ProxyLinkConfig.Kind) throws -> [String: Any] {
        XrayConfiguration.outbound(for: try ProxyLinkConfig(parsing: text, kind: kind))
    }

    private func settings(_ outbound: [String: Any], _ key: String) throws -> [String: Any] {
        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let servers = try XCTUnwrap(settings[key] as? [[String: Any]])
        return try XCTUnwrap(servers.first)
    }

    func testAShadowsocksOutboundCarriesTheLinksOwnCipher() throws {
        let outbound = try outbound(shadowsocks, .shadowsocks)
        let server = try settings(outbound, "servers")

        XCTAssertEqual(outbound["protocol"] as? String, "shadowsocks")
        XCTAssertEqual(server["address"] as? String, "vpn.example.com")
        XCTAssertEqual(server["port"] as? Int, 8388)
        XCTAssertEqual(server["method"] as? String, "aes-256-gcm")
        XCTAssertEqual(server["password"] as? String, "secret")
    }

    func testARealityOutboundCarriesTheHandshakeItIsHidingBehind() throws {
        let outbound = try outbound(reality, .vless)
        let user = try XCTUnwrap((try settings(outbound, "vnext")["users"]
                                  as? [[String: Any]])?.first)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let realityBlock = try XCTUnwrap(stream["realitySettings"] as? [String: Any])

        XCTAssertEqual(outbound["protocol"] as? String, "vless")
        XCTAssertEqual(user["id"] as? String, "3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f")
        XCTAssertEqual(user["encryption"] as? String, "none",
                       "VLESS carries no cipher of its own and Xray refuses a user without it")
        XCTAssertEqual(user["flow"] as? String, "xtls-rprx-vision")
        XCTAssertEqual(stream["security"] as? String, "reality")
        XCTAssertEqual(stream["network"] as? String, "tcp")
        XCTAssertEqual(realityBlock["serverName"] as? String, "www.microsoft.com")
        XCTAssertEqual(realityBlock["fingerprint"] as? String, "chrome")
        XCTAssertEqual(realityBlock["publicKey"] as? String, "xrK4Y_1n7Qk")
        XCTAssertEqual(realityBlock["shortId"] as? String, "9a3f")
    }

    func testARealityLinkWithNoFingerprintStillImitatesABrowser() throws {
        let outbound = try outbound(
            "vless://u@h.example.com:443?security=reality&pbk=k&sid=1", .vless)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])

        XCTAssertEqual((stream["realitySettings"] as? [String: Any])?["fingerprint"] as? String,
                       "chrome")
    }

    func testAPlainVLESSLinkGetsNoTLSBlock() throws {
        let outbound = try outbound(
            "vless://3f1c0e2a@vpn.example.com:8080?encryption=none&security=none", .vless)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])

        XCTAssertNil(stream["security"], "a link that asks for no TLS must not be given one")
        XCTAssertNil(stream["tlsSettings"])
        XCTAssertNil(stream["realitySettings"])
    }

    /// The two transports under the handshake that this build carries
    func testAWebSocketLinkCarriesItsPathAndHostHeader() throws {
        let outbound = try outbound(
            "vless://u@h.example.com:443?security=tls&type=ws&path=/vl&host=cdn.example.org&sni=a.b",
            .vless)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let ws = try XCTUnwrap(stream["wsSettings"] as? [String: Any])

        XCTAssertEqual(stream["network"] as? String, "ws")
        XCTAssertEqual(ws["path"] as? String, "/vl")
        XCTAssertEqual((ws["headers"] as? [String: String])?["Host"], "cdn.example.org")
        XCTAssertEqual((stream["tlsSettings"] as? [String: Any])?["serverName"] as? String, "a.b")
    }

    func testAGRPCLinkCarriesItsServiceName() throws {
        let outbound = try outbound(
            "vless://u@h.example.com:443?security=tls&type=grpc&serviceName=gun", .vless)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])

        XCTAssertEqual(stream["network"] as? String, "grpc")
        XCTAssertEqual((stream["grpcSettings"] as? [String: Any])?["serviceName"] as? String, "gun")
    }

    func testTheInboundIsTheSocksPortTun2SocksDials() throws {
        let json = try XrayConfiguration.json(forLink: shadowsocks, access: access)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let inbound = try XCTUnwrap((document["inbounds"] as? [[String: Any]])?.first)
        let settings = try XCTUnwrap(inbound["settings"] as? [String: Any])

        XCTAssertEqual(inbound["protocol"] as? String, "socks")
        XCTAssertEqual(inbound["listen"] as? String, "127.0.0.1",
                       "anything else is a proxy open to the network")
        XCTAssertEqual(inbound["port"] as? Int, access.port)
        XCTAssertEqual(settings["udp"] as? Bool, true, "without UDP there is no DNS")
        let yaml = Tun2SocksConfiguration.yaml(access: access)
        XCTAssertTrue(yaml.contains("port: \(access.port)"),
                      "the two halves have to name the same port")
        XCTAssertTrue(yaml.contains("username: \(access.username)"))
        XCTAssertTrue(yaml.contains("password: \(access.password)"))
    }

    func testTheInboundAnswersOnlyToTheSessionLogin() throws {
        let json = try XrayConfiguration.json(forLink: shadowsocks, access: access)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let inbound = try XCTUnwrap((document["inbounds"] as? [[String: Any]])?.first)
        let settings = try XCTUnwrap(inbound["settings"] as? [String: Any])
        let accounts = try XCTUnwrap(settings["accounts"] as? [[String: String]])

        XCTAssertEqual(settings["auth"] as? String, "password")
        XCTAssertEqual(accounts, [["user": access.username, "pass": access.password]])
    }

    func testEverySessionGetsItsOwnPortAndLogin() {
        let first = LocalProxyAccess.random()
        let second = LocalProxyAccess.random()
        XCTAssertNotEqual(first.username, second.username)
        XCTAssertNotEqual(first.password, second.password)
        XCTAssertEqual(first.username.count, 32)
        XCTAssertTrue((1024...65535).contains(first.port))
    }

    /// Traffic takes the server; DNS takes Xray's own resolver
    func testDNSIsAnsweredByXrayAndTrafficTakesTheServer() throws {
        let json = try XrayConfiguration.json(forLink: reality, access: access, dns: ["10.53.0.53"])
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let outbounds = try XCTUnwrap(document["outbounds"] as? [[String: Any]])
        let rules = try XCTUnwrap((document["routing"] as? [String: Any])?["rules"] as? [[String: Any]])

        XCTAssertEqual(outbounds.map { $0["tag"] as? String }, ["proxy", "dns-out", "block"],
                       "the server stays the default")
        XCTAssertEqual(outbounds[1]["protocol"] as? String, "dns")
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(rules.first?["port"] as? String, "53")
        XCTAssertEqual(rules.first?["outboundTag"] as? String, "dns-out")
        XCTAssertEqual(rules[1]["inboundTag"] as? [String], ["dns-query"])
        XCTAssertEqual(rules[1]["outboundTag"] as? String, "proxy",
                       "Xray's own questions reach a private resolver through the server")
        XCTAssertEqual(rules[2]["port"] as? String, "443", "QUIC is refused")
        XCTAssertEqual(rules[2]["network"] as? String, "udp")
        XCTAssertEqual(rules[2]["outboundTag"] as? String, "block")
        let dns = try XCTUnwrap(document["dns"] as? [String: Any])
        XCTAssertEqual(dns["servers"] as? [String], ["10.53.0.53"])
        XCTAssertEqual(dns["tag"] as? String, "dns-query")
    }

    /// Private addresses are refused on the device itself
    func testPrivateAddressesAreRefusedOnTheDevice() throws {
        let json = try XrayConfiguration.json(forLink: reality, access: access)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let rules = try XCTUnwrap((document["routing"] as? [String: Any])?["rules"] as? [[String: Any]])
        let last = try XCTUnwrap(rules.last)
        XCTAssertEqual(last["outboundTag"] as? String, "block")
        let ranges = try XCTUnwrap(last["ip"] as? [String])
        for range in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "fc00::/7", "fe80::/10"] {
            XCTAssertTrue(ranges.contains(range), range)
        }
        XCTAssertNil(last["port"], "every port, every protocol")
    }

    func testAResolvedServerAddressKeepsTheNameForTheHandshake() throws {
        let link = "vless://u@vpn.example.com:443?security=reality&pbk=k&sid=1"
        let json = try XrayConfiguration.json(forLink: link, access: access,
                                              serverAddress: "203.0.113.9")
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let outbound = try XCTUnwrap((document["outbounds"] as? [[String: Any]])?.first)
        let vnext = try XCTUnwrap(((outbound["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])?.first)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let reality = try XCTUnwrap(stream["realitySettings"] as? [String: Any])

        XCTAssertEqual(vnext["address"] as? String, "203.0.113.9")
        XCTAssertEqual(reality["serverName"] as? String, "vpn.example.com")
    }

    func testAnUnreadableLinkNeverBecomesAConfiguration() {
        XCTAssertThrowsError(try XrayConfiguration.json(forLink: "not a link", access: access))
    }

    func testATransportWithNoBranchIsRefusedByName() {
        XCTAssertThrowsError(
            try XrayConfiguration.json(
                forLink: "vless://u@h.example.com:443?security=tls&type=quic", access: access)) { error in
            XCTAssertEqual(error as? ProxyLinkConfig.ParseError, .unsupportedTransport("quic"))
        }
        XCTAssertThrowsError(
            try XrayConfiguration.json(
                forLink: "vless://u@h.example.com:443?security=xtls", access: access)) { error in
            XCTAssertEqual(error as? ProxyLinkConfig.ParseError, .unsupportedTransport("xtls"))
        }
    }

    func testTheTunnelAddressIsStatedOnce() {
        let yaml = Tun2SocksConfiguration.yaml(access: access)
        XCTAssertTrue(yaml.contains("ipv4: \(Tun2SocksConfiguration.address)"))
        XCTAssertTrue(yaml.contains("mtu: \(Tun2SocksConfiguration.mtu)"))
        XCTAssertTrue(yaml.contains("tcp-buffer-size: 4096"), "each connection keeps a small buffer")
        XCTAssertTrue(yaml.contains("task-stack-size: 24576"))
        XCTAssertTrue(yaml.contains("udp-read-write-timeout: 10000"), "silent UDP flows close soon")
        XCTAssertTrue(yaml.contains("max-session-count: 128"))
        XCTAssertTrue(yaml.contains("ipv6: '\(Tun2SocksConfiguration.address6)'"),
                      "IPv6 is routed into the tunnel, so the packet stack must answer on it")
    }
}

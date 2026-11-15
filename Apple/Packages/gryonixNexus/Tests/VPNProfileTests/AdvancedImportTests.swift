import XCTest
@testable import VPNProfile

final class AdvancedImportTests: XCTestCase {
    private let vless = "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@a.example.net:443"
        + "?security=reality&sni=www.example.org&fp=chrome&pbk=KEY&sid=9a&type=tcp&flow=xtls-rprx-vision#Berlin"
    private let trojan = "trojan://secret@b.example.net:443?sni=b.example.net&type=ws&path=%2Fws#Paris"
    private let ss = "ss://YWVzLTI1Ni1nY206cGFzcw@c.example.net:8388#Oslo"
    private var vmess: String {
        let json = #"{"v":"2","ps":"Rome","add":"d.example.net","port":"443","id":"uuid-1","aid":"0","net":"ws","tls":"tls","path":"/p","host":"h.example.net"}"#
        return "vmess://" + Data(json.utf8).base64EncodedString()
    }

    func testBase64SubscriptionListsSupportedLinks() {
        let list = [vless, vmess, trojan, ss, "tuic://x@h.example.net:443#Fast"].joined(separator: "\n")
        let body = Data(list.utf8).base64EncodedString()
        let report = SubscriptionImport.parse(body: body)
        XCTAssertEqual(report.servers.map(\.kind), [.vless, .vmess, .trojan, .shadowsocks])
        XCTAssertEqual(report.servers.map(\.name), ["Berlin", "Rome", "Paris", "Oslo"])
        XCTAssertEqual(report.unsupported.count, 1)
        XCTAssertTrue(report.unsupported[0].reason.contains("tuic"))
    }

    func testLinkFields() throws {
        let server = try SubscriptionImport.parse(link: vless).get()
        XCTAssertEqual(server.fields["pbk"], "KEY")
        XCTAssertEqual(server.fields["flow"], "xtls-rprx-vision")
        let ws = try SubscriptionImport.parse(link: vmess).get()
        XCTAssertEqual(ws.fields["network"], "ws")
        XCTAssertEqual(ws.fields["host"], "h.example.net")
        let shadow = try SubscriptionImport.parse(link: ss).get()
        XCTAssertEqual(shadow.fields["method"], "aes-256-gcm")
    }

    func testShadowsocks2022IsKeptAndPluginsAreSkipped() throws {
        let ss2022 = "ss://" + Data("2022-blake3-aes-256-gcm:key".utf8).base64EncodedString() + "@e.example.net:1#X"
        let server = try SubscriptionImport.parse(link: ss2022).get()
        XCTAssertTrue(AdvancedXrayConfiguration.isShadowsocks2022(server))
        XCTAssertNil(try? SubscriptionImport.parse(link: "ss://YWVzLTI1Ni1nY206cGFzcw@c.example.net:8388?plugin=obfs#Oslo").get())
    }

    func testClashProxiesAndRules() {
        let yaml = """
        proxies:
          - {name: "HK 1", type: ss, server: h.example.net, port: 8388, cipher: aes-128-gcm, password: pw}
          - name: DE
            type: vless
            server: de.example.net
            port: 443
            uuid: abc
            tls: true
            servername: de.example.net
            network: ws
            ws-opts:
              path: /ws
              headers:
                Host: cdn.example.net
          - {name: Fast, type: hysteria2, server: f.example.net, port: 1}
        rules:
          - DOMAIN-SUFFIX,example.org,DIRECT
          - DOMAIN-KEYWORD,ads,REJECT # comment
          - IP-CIDR,10.1.0.0/16,Proxy,no-resolve
          - PROCESS-NAME,app,DIRECT
          - MATCH,Proxy
        """
        let report = ClashImport.parse(yaml)
        XCTAssertEqual(report.servers.map(\.name), ["HK 1", "DE"])
        XCTAssertEqual(report.servers[1].fields["host"], "cdn.example.net")
        XCTAssertEqual(report.servers[1].fields["path"], "/ws")
        XCTAssertEqual(report.rules.map(\.action), [.direct, .block, .proxy])
        XCTAssertEqual(report.rules.map(\.kind), [.domainSuffix, .keyword, .ip])
        XCTAssertEqual(report.unsupported.count, 3)
    }

    func testHysteria2AndNaiveLinks() throws {
        let hy = try SubscriptionImport.parse(
            link: "hy2://secret@h.example.net:8443/?sni=s.example.net&obfs=salamander&obfs-password=o&insecure=1#Fast").get()
        XCTAssertEqual(hy.kind, .hysteria2)
        XCTAssertEqual(hy.port, 8443)
        XCTAssertEqual(hy.fields["password"], "secret")
        XCTAssertEqual(hy.fields["obfsPassword"], "o")
        XCTAssertNil(try? SubscriptionImport.parse(link: "hysteria2://s@h.example.net:443,2000-3000#R").get())
        let naive = try SubscriptionImport.parse(link: "naive+https://me:pw@n.example.net#N").get()
        XCTAssertEqual(naive.kind, .naive)
        XCTAssertEqual(naive.port, 443)
        XCTAssertEqual(naive.fields["user"], "me")
        XCTAssertEqual(naive.fields["password"], "pw")
    }

    func testClashHysteria2AndShadowsocks2022() {
        let yaml = """
        proxies:
          - {name: H, type: hysteria2, server: h.example.net, port: 443, password: pw, obfs: salamander, obfs-password: o}
          - {name: S, type: ss, server: s.example.net, port: 1, cipher: 2022-blake3-aes-128-gcm, password: k}
          - {name: T, type: tuic, server: t.example.net, port: 1}
        """
        let report = ClashImport.parse(yaml)
        XCTAssertEqual(report.servers.map(\.kind), [.hysteria2, .shadowsocks])
        XCTAssertEqual(report.servers[0].fields["obfs"], "salamander")
        XCTAssertEqual(report.unsupported.map(\.name), ["T"])
    }

    func testGeoIPDatKeepsWantedCountries() throws {
        let data = GeoIPFixture.dat([("RU", [[10, 0, 0, 0]], 8), ("CN", [[1, 2, 3, 0]], 24),
                                     ("DE", [[0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 12)], 32)])
        let ranges = try GeoIPDatParser.ranges(in: data, codes: ["CN", "DE"])
        XCTAssertEqual(ranges["CN"], ["1.2.3.0/24"])
        XCTAssertEqual(ranges["DE"], ["2001:db8:0:0:0:0:0:0/32"])
        XCTAssertNil(ranges["RU"])
        XCTAssertThrowsError(try GeoIPDatParser.ranges(in: Data([0x0A, 0x50]), codes: ["CN"]))
    }

    func testSubscriptionBodyThatIsClash() {
        let report = SubscriptionImport.parse(body: "proxies:\n  - {name: A, type: trojan, server: t.example.net, port: 443, password: p}\n")
        XCTAssertEqual(report.servers.first?.kind, .trojan)
    }

    func testBlockListFormats() {
        let text = "# list\n0.0.0.0 ads.example.net\n||track.example.org^\nplain.example.com\n127.0.0.1 localhost\n! note\n"
        XCTAssertEqual(BlockListParser.domains(in: text),
                       ["ads.example.net", "track.example.org", "plain.example.com"])
    }
}

enum GeoIPFixture {
    /// A GeoIPList with one network per country
    static func dat(_ countries: [(String, [[UInt8]], UInt8)]) -> Data {
        var list: [UInt8] = []
        for (code, addresses, prefix) in countries {
            var entry = field(1, Array(code.utf8))
            for address in addresses { entry += field(2, field(1, address) + [0x10, prefix]) }
            list += field(1, entry)
        }
        return Data(list)
    }

    private static func field(_ number: UInt8, _ bytes: [UInt8]) -> [UInt8] {
        var length = bytes.count
        var varint: [UInt8] = []
        repeat {
            varint.append(UInt8(length & 0x7F) | (length > 0x7F ? 0x80 : 0))
            length >>= 7
        } while length > 0
        return [number << 3 | 2] + varint + bytes
    }
}

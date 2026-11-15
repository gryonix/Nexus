import XCTest
@testable import VPNProfile

final class AdvancedXrayConfigurationTests: XCTestCase {
    private let access = LocalProxyAccess(port: 40123, username: "u", password: "p")

    private func server(_ name: String, _ host: String) -> AdvancedServer {
        AdvancedServer(kind: .trojan, name: name, host: host, port: 443,
                       fields: ["password": "pw", "network": "tcp", "security": "tls", "sni": host])
    }

    private func profile() -> AdvancedProfile {
        var profile = AdvancedProfile()
        profile.servers = [server("A", "a.example.net"), server("B", "b.example.net")]
        profile.activeID = profile.servers[0].id
        return profile
    }

    private func build(_ profile: AdvancedProfile, options: AdvancedXrayConfiguration.Options = .init()) throws -> [String: Any] {
        try AdvancedXrayConfiguration.document(profile: profile, access: access, options: options)
    }

    private func rules(_ document: [String: Any]) -> [[String: Any]] {
        (document["routing"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
    }

    func testRulesKeepOrderAndMergeNeighbours() throws {
        var profile = profile()
        profile.rules = [
            AdvancedRule(kind: .domainSuffix, value: "example.org", action: .direct),
            AdvancedRule(kind: .domain, value: "www.example.com", action: .direct),
            AdvancedRule(kind: .keyword, value: "ads", action: .block),
            AdvancedRule(kind: .ip, value: "203.0.113.0/24", action: .proxy),
        ]
        profile.finalAction = .direct
        let list = rules(try build(profile))
        let user = list.filter { $0["domain"] != nil || $0["ip"] as? [String] == ["203.0.113.0/24"] }
        XCTAssertEqual(user[0]["domain"] as? [String], ["domain:example.org", "full:www.example.com"])
        XCTAssertEqual(user[0]["outboundTag"] as? String, "direct")
        XCTAssertEqual(user[1]["domain"] as? [String], ["keyword:ads"])
        XCTAssertEqual(user[1]["outboundTag"] as? String, "block")
        XCTAssertEqual(user[2]["outboundTag"] as? String, "proxy")
        XCTAssertEqual(list.last?["outboundTag"] as? String, "direct")
        XCTAssertEqual((try build(profile)["routing"] as? [String: Any])?["domainStrategy"] as? String, "IPIfNonMatch")
    }

    func testGeoIPUsesDownloadedNetworks() throws {
        var profile = profile()
        profile.rules = [AdvancedRule(kind: .geoip, value: "cn", action: .direct),
                         AdvancedRule(kind: .ip, value: "203.0.113.0/24", action: .direct)]
        XCTAssertEqual(AdvancedXrayConfiguration.skippedRules(profile).count, 1)
        XCTAssertEqual(rules(try build(profile)).filter { $0["outboundTag"] as? String == "direct" }.count, 1)
        profile.geoip.ranges = ["CN": ["1.0.1.0/24", "1.0.2.0/23"]]
        XCTAssertTrue(AdvancedXrayConfiguration.skippedRules(profile).isEmpty)
        let merged = rules(try build(profile)).first { ($0["ip"] as? [String])?.first == "1.0.1.0/24" }
        XCTAssertEqual(merged?["ip"] as? [String], ["1.0.1.0/24", "1.0.2.0/23", "203.0.113.0/24"])
        XCTAssertEqual(AdvancedGeoIP.codes(in: profile.rules + [AdvancedRule(kind: .geoip, value: "private", action: .direct)]), ["CN"])
    }

    func testHysteria2NaiveAndShadowsocks2022Outbounds() throws {
        var profile = profile()
        let hy = AdvancedServer(kind: .hysteria2, name: "H", host: "h.example.net", port: 443,
                                fields: ["password": "pw", "obfs": "salamander", "obfsPassword": "o"])
        let naive = AdvancedServer(kind: .naive, name: "N", host: "n.example.net", port: 443,
                                   fields: ["user": "me", "password": "pw"])
        let ss = AdvancedServer(kind: .shadowsocks, name: "S", host: "s.example.net", port: 8388,
                                fields: ["method": "2022-blake3-aes-128-gcm", "password": "k"])
        profile.servers = [hy, naive, ss]
        let group = AdvancedGroup(name: "Auto", mode: .auto, memberIDs: profile.servers.map(\.id))
        profile.groups = [group]
        profile.activeID = group.id
        XCTAssertEqual(AdvancedXrayConfiguration.ss2022Members(of: profile).map(\.id), [ss.id])
        let outbounds = try XCTUnwrap(try build(profile, options: .init(ss2022Ports: [ss.id: 41000]))["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds[0]["protocol"] as? String, "hysteria")
        let stream = try XCTUnwrap(outbounds[0]["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["network"] as? String, "hysteria")
        XCTAssertEqual((stream["hysteriaSettings"] as? [String: Any])?["auth"] as? String, "pw")
        XCTAssertNotNil(stream["finalmask"])
        XCTAssertEqual(outbounds[1]["protocol"] as? String, "http")
        XCTAssertEqual((outbounds[1]["settings"] as? [String: Any])?["user"] as? String, "me")
        XCTAssertEqual(outbounds[2]["protocol"] as? String, "socks")
        XCTAssertTrue(String(describing: outbounds[2]).contains("41000"))
        XCTAssertTrue(String(describing: outbounds[2]).contains("\"u\""))
    }

    func testDoTRunsThroughALoopbackBridge() throws {
        var profile = profile()
        let dot = AdvancedDNSUpstream(kind: .dot, address: "dns.example.net", domains: ["example.org"])
        let skipped = AdvancedDNSUpstream(kind: .dot, address: "other.example.net")
        profile.dns = [dot, skipped]
        let options = AdvancedXrayConfiguration.Options(resolved: ["dns.example.net": "198.51.100.1"], dotPorts: [dot.id: 41001])
        let document = try build(profile, options: options)
        let servers = try XCTUnwrap((document["dns"] as? [String: Any])?["servers"] as? [Any])
        XCTAssertEqual((servers[0] as? [String: Any])?["address"] as? String, "tcp+local://127.0.0.1:41001")
        XCTAssertEqual(servers.count, 1 + ProxyTunnelText.fallbackDNS.count)
        let inbound = try XCTUnwrap((document["inbounds"] as? [[String: Any]])?.last)
        XCTAssertEqual(inbound["port"] as? Int, 41001)
        XCTAssertEqual((inbound["settings"] as? [String: Any])?["address"] as? String, "198.51.100.1")
        XCTAssertEqual((inbound["settings"] as? [String: Any])?["port"] as? Int, 853)
        let bridge = try XCTUnwrap((document["outbounds"] as? [[String: Any]])?.last)
        XCTAssertEqual(bridge["protocol"] as? String, "freedom")
        XCTAssertEqual((bridge["proxySettings"] as? [String: Any])?["tag"] as? String, "proxy")
        XCTAssertEqual(rules(document).first?["outboundTag"] as? String, "dot-0")
        XCTAssertEqual(AdvancedXrayConfiguration.endpoint(ofDoT: "[2001:db8::1]:8853")?.port, 8853)
        XCTAssertEqual(AdvancedXrayConfiguration.endpoint(ofDoT: "2001:db8::1")?.host, "2001:db8::1")
    }

    func testHostRewritesOnlyWhenEnabled() throws {
        var profile = profile()
        profile.hosts = [AdvancedHostRewrite(domain: "a.example.org", target: "203.0.113.9")]
        XCTAssertNil((try build(profile)["dns"] as? [String: Any])?["hosts"])
        profile.rewritesEnabled = true
        let hosts = (try build(profile)["dns"] as? [String: Any])?["hosts"] as? [String: String]
        XCTAssertEqual(hosts, ["full:a.example.org": "203.0.113.9"])
    }

    func testOldProfileJSONStillDecodes() throws {
        let old = #"{"servers":[],"groups":[],"rules":[],"finalAction":"direct","dns":[],"blockLists":[],"subscriptions":[],"collectsTraffic":true}"#
        let decoded = try JSONDecoder().decode(AdvancedProfile.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.finalAction, .direct)
        XCTAssertTrue(decoded.collectsTraffic)
        XCTAssertFalse(decoded.rewritesEnabled)
        XCTAssertEqual(decoded.geoip.url, AdvancedGeoIP.defaultURL)
    }

    func testAutoGroupBuildsLeastPingBalancer() throws {
        var profile = profile()
        let group = AdvancedGroup(name: "Auto", mode: .auto, memberIDs: profile.servers.map(\.id))
        profile.groups = [group]
        profile.activeID = group.id
        let document = try build(profile)
        let routing = try XCTUnwrap(document["routing"] as? [String: Any])
        let balancer = try XCTUnwrap((routing["balancers"] as? [[String: Any]])?.first)
        XCTAssertEqual(balancer["selector"] as? [String], ["s0", "s1"])
        XCTAssertEqual((balancer["strategy"] as? [String: Any])?["type"] as? String, "leastPing")
        let observatory = try XCTUnwrap(document["observatory"] as? [String: Any])
        XCTAssertEqual(observatory["subjectSelector"] as? [String], ["s0", "s1"])
        XCTAssertEqual(rules(document).last?["balancerTag"] as? String, "auto")
        let tags = (document["outbounds"] as? [[String: Any]])?.compactMap { $0["tag"] as? String }
        XCTAssertEqual(Array((tags ?? []).prefix(2)), ["s0", "s1"])
    }

    func testManualGroupUsesTheChosenServerOnly() throws {
        var profile = profile()
        let group = AdvancedGroup(name: "Pick", mode: .manual, memberIDs: profile.servers.map(\.id),
                                  selectedID: profile.servers[1].id)
        profile.groups = [group]
        profile.activeID = group.id
        let document = try build(profile)
        XCTAssertNil(document["observatory"])
        let first = (document["outbounds"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["tag"] as? String, "proxy")
        XCTAssertTrue(String(describing: first).contains("b.example.net"))
    }

    func testDNSUpstreams() throws {
        var profile = profile()
        profile.dns = [
            AdvancedDNSUpstream(kind: .doh, address: "dns.example.net", domains: ["example.org"], viaProxy: false),
            AdvancedDNSUpstream(kind: .doh, address: "https://doh.example.net/dns-query"),
            AdvancedDNSUpstream(kind: .doq, address: "q.example.net"),
        ]
        let dns = try XCTUnwrap(try build(profile)["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [Any])
        let scoped = try XCTUnwrap(servers[0] as? [String: Any])
        XCTAssertEqual(scoped["address"] as? String, "https+local://dns.example.net/dns-query")
        XCTAssertEqual(scoped["domains"] as? [String], ["domain:example.org"])
        XCTAssertEqual(servers[1] as? String, "https://doh.example.net/dns-query")
        XCTAssertEqual(servers[2] as? String, "quic+local://q.example.net")
        XCTAssertEqual(servers.last as? String, "8.8.8.8")
    }

    func testBlockListBecomesBlockRule() throws {
        var profile = profile()
        profile.blockLists = [AdvancedBlockList(url: "https://example.net/l.txt", domains: ["ads.example.net"])]
        let block = rules(try build(profile)).first { ($0["domain"] as? [String]) == ["domain:ads.example.net"] }
        XCTAssertEqual(block?["outboundTag"] as? String, "block")
    }

    func testResolvedAddressKeepsServerName() throws {
        let options = AdvancedXrayConfiguration.Options(resolved: ["a.example.net": "203.0.113.5"])
        let outbounds = try XCTUnwrap(try build(profile(), options: options)["outbounds"] as? [[String: Any]])
        let text = String(describing: outbounds[0])
        XCTAssertTrue(text.contains("203.0.113.5"))
        XCTAssertTrue(text.contains("a.example.net"))
    }

    func testStatsAddsApi() throws {
        let document = try build(profile(), options: .init(statsPort: 10085))
        XCTAssertNotNil(document["stats"])
        XCTAssertEqual((document["metrics"] as? [String: String])?["listen"], "127.0.0.1:10085")
    }

    func testNoActiveTargetThrows() {
        XCTAssertThrowsError(try build(AdvancedProfile()))
    }
}

final class AdvancedTrafficTests: XCTestCase {
    func testStatsSplitDirectAndProxy() {
        let json = """
        {"stats":{"outbound":{
          "proxy":{"uplink":100,"downlink":900},
          "direct":{"uplink":5,"downlink":20},
          "block":{"uplink":1}
        },"inbound":{"socks-in":{"uplink":7}}}}
        """
        let traffic = AdvancedTraffic.counters(fromMetrics: Data(json.utf8))
        XCTAssertEqual(traffic.proxy, .init(uploaded: 100, downloaded: 900))
        XCTAssertEqual(traffic.direct, .init(uploaded: 5, downloaded: 20))
    }

    func testAccessLogLines() {
        let log = """
        2026/11/07 10:00:01 from tcp:127.0.0.1:5000 accepted tcp:www.example.com:443 [socks-in -> direct]
        2026/11/07 10:00:02 from tcp:127.0.0.1:5001 accepted udp:ads.example.net:443 [socks-in -> block]
        noise
        """
        let requests = AdvancedTraffic.requests(fromLog: log)
        XCTAssertEqual(requests.map(\.domain), ["www.example.com", "ads.example.net"])
        XCTAssertEqual(requests.map(\.route), ["direct", "block"])
    }

    func testAdvancedLineSurvivesTunnelText() {
        let text = ProxyTunnelText.compose(link: "advanced", dns: ["9.9.9.9"], advanced: "{\"a\":1}")
        XCTAssertEqual(ProxyTunnelText.split(text).link, "advanced")
        XCTAssertEqual(ProxyTunnelText.split(text).dns, ["9.9.9.9"])
        XCTAssertEqual(ProxyTunnelText.advancedJSON(in: text), "{\"a\":1}")
    }
}

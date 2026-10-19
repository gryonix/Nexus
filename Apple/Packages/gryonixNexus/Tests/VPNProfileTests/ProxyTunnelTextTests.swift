import XCTest
@testable import VPNProfile

final class ProxyTunnelTextTests: XCTestCase {
    private let link = "vless://id@vpn.example.net:443?security=reality#phone"

    func testTheLinkComesBackUntouchedWithItsDNS() {
        let text = ProxyTunnelText.compose(link: link, dns: ["9.9.9.9", "2620:fe::fe"])
        let (back, dns) = ProxyTunnelText.split(text)
        XCTAssertEqual(back, link)
        XCTAssertEqual(dns, ["9.9.9.9", "2620:fe::fe"])
    }

    func testALinkStoredBeforeKeepsTheOldDNS() {
        let (back, dns) = ProxyTunnelText.split(link)
        XCTAssertEqual(back, link)
        XCTAssertEqual(dns, ["1.1.1.1", "8.8.8.8"])
    }

    func testNoDNSLeavesTheLinkAlone() {
        XCTAssertEqual(ProxyTunnelText.compose(link: link, dns: []), link)
    }

    func testTheTunnelAsksIPv4ResolversWhenTheListHasThem() {
        let cloudflare = ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"]
        XCTAssertEqual(ProxyTunnelText.reachableDNS(cloudflare), ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(ProxyTunnelText.reachableDNS(["2620:fe::fe"]), ["2620:fe::fe"])
    }
}

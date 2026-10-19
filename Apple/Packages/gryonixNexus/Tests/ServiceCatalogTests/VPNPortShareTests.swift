import XCTest
@testable import ServiceCatalog

final class VPNPortShareTests: XCTestCase {
    private func context(_ services: Set<ServiceID>) -> ServiceContext {
        ServiceContext(domain: "example.com", sshUser: "admin", installedServices: services)
    }

    func testThePortIsSharedOnlyWithBothProtocols() {
        XCTAssertEqual(VPNPortShare.sharedPort(context([.wireguardVPN, .amneziaWG])), 51820)
        XCTAssertNil(VPNPortShare.sharedPort(context([.amneziaWG])))
        XCTAssertNil(VPNPortShare.sharedPort(context([.wireguardVPN])))
        XCTAssertEqual(VPNPortShare.clientPort(context([.amneziaWG])), 51822)
    }

    func testTheDropInReplacesItsOwnTableAndMovesOtherFlows() {
        let text = VPNPortShare.dropIn(wireGuardPort: 51821, amneziaPort: 51822)
        XCTAssertTrue(text.contains("table inet gryonixnexus_vpn_share\ndelete table inet gryonixnexus_vpn_share\n"))
        XCTAssertTrue(text.contains("udp dport 51821 @th,64,32 != { 0x01000000, 0x02000000, 0x03000000, "
                                    + "0x04000000 } redirect to :51822\n"))
        XCTAssertTrue(text.hasSuffix("    }\n}\n"))
    }

    func testTheSectionClearsTheShareWhenAProtocolIsMissing() {
        let alone = VPNPortShare.section(context([.amneziaWG]))
        XCTAssertTrue(alone.contains("rm -f /etc/nftables.d/gryonixnexus-svc-vpn-share.nft"))
        XCTAssertTrue(alone.contains("nft delete table inet gryonixnexus_vpn_share 2>/dev/null || true"))
        let both = VPNPortShare.section(context([.wireguardVPN, .amneziaWG]))
        XCTAssertTrue(both.contains("redirect to :51822\n    }\n}\nEOF_VPN_SHARE\nnft -f "))
        XCTAssertEqual(AmneziaWGVPNService().reportSteps(context([.wireguardVPN, .amneziaWG])).first?
            .contains("vpn.example.com:51820 (UDP)"), true)
    }
}

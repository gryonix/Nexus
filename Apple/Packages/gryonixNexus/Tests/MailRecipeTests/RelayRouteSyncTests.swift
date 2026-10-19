import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class RelayRouteSyncTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    private func access() -> DashboardAccessInput {
        DashboardAccessInput(sshUser: "admin", appPublicKey: appKey)
    }

    private func inputB(services: Set<ServiceID> = [.vaultwarden]) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            dashboardAccess: access(),
            services: services
        )
    }

    private func scripts(_ services: Set<ServiceID> = [.vaultwarden]) throws -> (vps: String, home: String) {
        let bundle = try MailRecipe().generate(from: try inputB(services: services))
        let vps = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-vps.sh" }).contents
        let home = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-home-server.sh" }).contents
        return (vps, home)
    }

    private func ruleset(in script: String) throws -> String {
        try XCTUnwrap(
            script.components(separatedBy: "<<'EOF_NFT'\n").dropFirst().first?
                .components(separatedBy: "\nEOF_NFT").first,
            "no nftables ruleset in the script"
        )
    }

    /// The uninstall wrapper heredoc, sliced out of the setup script
    private func uninstallWrapper(in script: String) throws -> String {
        let start = try XCTUnwrap(script.range(of: "cat > /opt/gryonixnexus-uninstall.sh <<'EOF_UNINSTALL'\n"))
        let end = try XCTUnwrap(script.range(of: "\nEOF_UNINSTALL", range: start.upperBound..<script.endIndex))
        return String(script[start.upperBound..<end.lowerBound])
    }

    // MARK: - Home ruleset: the marking chain

    func testHomePrerouteChainMarksAndRestoresTunnelOriginatedConnections() throws {
        let (_, home) = try scripts()
        let nft = try ruleset(in: home)
        XCTAssertTrue(nft.contains("chain prerouting {"), "home needs a chain to mark relayed connections")
        XCTAssertTrue(nft.contains("type filter hook prerouting priority mangle; policy accept;"))
        XCTAssertTrue(nft.contains("ct state new iifname \"wg0\" ct mark set 0x1"),
                      "new connections from the tunnel get marked")
        XCTAssertTrue(nft.contains("meta mark set ct mark"),
                      "the mark must be restored onto every packet, or `ip rule` never sees it")
        XCTAssertFalse(nft.contains("chain forward"))
        XCTAssertTrue(nft.contains("oifname \"wg0\" meta mark 0x1 masquerade"),
                      "the host reaches its own public names through the tunnel")
    }

    func testSingleHostRulesetHasNoPrerouteMarking() throws {
        let bundle = try MailRecipe().generate(from: MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: [.vaultwarden]
        ))
        let script = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }).contents
        XCTAssertFalse(script.contains("chain prerouting"))
        XCTAssertFalse(script.contains("chain output"))
    }

    func testHomeOutputChainRestoresTheMarkOnLocallyGeneratedReplies() throws {
        let (_, home) = try scripts()
        let nft = try ruleset(in: home)
        XCTAssertTrue(nft.contains("chain output {"),
                      "replies from a local process (Caddy, mail) need their mark restored too")
        XCTAssertTrue(nft.contains("type route hook output priority mangle; policy accept;"),
                      "`type route` is what makes the kernel redo the route lookup after the mark changes")
        let outputChain = try XCTUnwrap(
            nft.range(of: "chain output {").map { String(nft[$0.lowerBound...]) }
        )
        XCTAssertTrue(outputChain.contains("meta mark set ct mark"))
    }

    // MARK: - Home sysctl: rp_filter, no ip_forward

    func testHomeSysctlLoosensRpFilterWithoutEnablingForwarding() throws {
        let (_, home) = try scripts()
        let sysctl = try XCTUnwrap(
            home.components(separatedBy: "<<'EOF_SYSCTL'\n").dropFirst().first?
                .components(separatedBy: "\nEOF_SYSCTL").first,
            "no sysctl file in the home script"
        )
        XCTAssertTrue(sysctl.contains("net.ipv4.conf.all.rp_filter = 2"))
        XCTAssertTrue(sysctl.contains("net.ipv4.conf.default.rp_filter = 2"))
        XCTAssertFalse(sysctl.contains("ip_forward"),
                       "home does not route between two external interfaces the way the relay does")
        XCTAssertTrue(home.contains("/etc/sysctl.d/99-gryonixnexus-rpfilter.conf"),
                      "a different file than the relay's own forwarding sysctl")
    }

    func testVPSSysctlStillEnablesForwarding() throws {
        // The relay's own sysctl is untouched by this change.
        let (vps, _) = try scripts()
        XCTAssertTrue(vps.contains("net.ipv4.ip_forward = 1"))
        XCTAssertTrue(vps.contains("/etc/sysctl.d/99-gryonixnexus-forwarding.conf"))
    }

    // MARK: - Home setup script: the route-sync script + units, in order

    func testHomeScriptInstallsRouteSyncAfterTheHandshakeSucceeds() throws {
        let (_, home) = try scripts()
        XCTAssertTrue(home.contains("cat > /opt/gryonixnexus-relay-route-sync.sh"))
        XCTAssertTrue(home.contains("cat > /etc/systemd/system/gryonixnexus-relay-route-sync.service"))
        XCTAssertTrue(home.contains("cat > /etc/systemd/system/gryonixnexus-relay-route-sync.timer"))
        XCTAssertTrue(home.contains("systemctl enable --now gryonixnexus-relay-route-sync.timer"))
        XCTAssertTrue(home.contains("systemctl start gryonixnexus-relay-route-sync.service"),
                      "the very tunnel this setup run uses needs the route now, not at the timer's first tick")

        let handshake = try XCTUnwrap(home.range(of: "waitingForHandshake") ?? home.range(of: "wg show wg0 latest-handshakes"))
        let install = try XCTUnwrap(home.range(of: "cat > /opt/gryonixnexus-relay-route-sync.sh"))
        let activation = try XCTUnwrap(home.range(of: "systemctl enable --now gryonixnexus-relay-route-sync.timer"))
        XCTAssertLessThan(handshake.lowerBound, install.lowerBound,
                          "route-sync must install after the tunnel handshake, not before")
        XCTAssertLessThan(install.lowerBound, activation.lowerBound)

        let wgConfBlock = try XCTUnwrap(
            home.components(separatedBy: "<<'EOF_WG'\n").dropFirst().first?
                .components(separatedBy: "\nEOF_WG").first
        )
        XCTAssertFalse(wgConfBlock.contains("PostUp ="))
        XCTAssertFalse(wgConfBlock.contains("relay-route-sync"))
    }

    func testHomeScriptPinsTheRelayRouteOutsideTheTunnel() throws {
        let (_, home) = try scripts()
        XCTAssertTrue(home.contains("/etc/systemd/system/gryonixnexus-tunnel-endpoint.service"),
                      "without this the tunnel routes its own packets back into itself")
        XCTAssertTrue(home.contains("ip -4 route replace 203.0.113.10/32"),
                      "the relay's own address, pinned in the main table")
        XCTAssertTrue(home.contains("Before=wg-quick@wg0.service"),
                      "the route has to exist before the tunnel claims the default route")
        XCTAssertTrue(home.contains("table main"),
                      "the gateway is read from what the host used BEFORE the tunnel")

        let wgConfBlock = try XCTUnwrap(
            home.components(separatedBy: "<<'EOF_WG'\n").dropFirst().first?
                .components(separatedBy: "\nEOF_WG").first
        )
        XCTAssertFalse(wgConfBlock.contains("PreUp ="))
        XCTAssertFalse(wgConfBlock.contains("PostDown ="))
        XCTAssertTrue(wgConfBlock.contains("AllowedIPs = 0.0.0.0/0"),
                      "a split list here would put 32 prefixes in the main table, and docker " +
                      "then refuses to allocate any bridge subnet at all")
    }

    func testEraseRemovesTheEndpointRouteUnit() throws {
        let (_, home) = try scripts()
        XCTAssertTrue(home.contains("rm -f /etc/systemd/system/gryonixnexus-tunnel-endpoint.service"))
        XCTAssertTrue(home.contains("systemctl disable --now gryonixnexus-tunnel-endpoint.service"))
    }

    func testVPSScriptNeverInstallsHomeOnlyRouteSync() throws {
        let (vps, _) = try scripts()
        XCTAssertFalse(vps.contains("gryonixnexus-relay-route-sync"))
        XCTAssertFalse(vps.contains("99-gryonixnexus-rpfilter.conf"))
    }

    // MARK: - Uninstall: home only, scenario B

    func testHomeUninstallRemovesTheRouteSyncMechanism() throws {
        let (_, home) = try scripts()
        let wrapper = try uninstallWrapper(in: home)
        XCTAssertTrue(wrapper.contains("gryonixnexus-relay-route-sync.timer"))
        XCTAssertTrue(wrapper.contains("gryonixnexus-relay-route-sync.service"))
        XCTAssertTrue(wrapper.contains("rm -f '/opt/gryonixnexus-relay-route-sync.sh'"))
        XCTAssertTrue(wrapper.contains("ip rule del fwmark '0x1' table '100'"))
        XCTAssertTrue(wrapper.contains("ip route flush table '100'"))
        XCTAssertTrue(wrapper.contains("rm -f /etc/sysctl.d/99-gryonixnexus-rpfilter.conf"))
    }

    func testVPSUninstallNeverMentionsTheHomeOnlyRouteSync() throws {
        let (vps, _) = try scripts()
        XCTAssertFalse(vps.contains("gryonixnexus-relay-route-sync"))
        XCTAssertFalse(vps.contains("99-gryonixnexus-rpfilter.conf"))
    }
}

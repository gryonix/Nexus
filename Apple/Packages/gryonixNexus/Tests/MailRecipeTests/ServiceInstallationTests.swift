import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class ServiceInstallationTests: XCTestCase {
    private func inputA(services: Set<ServiceID>, hostname: String = "mail.example.com",
                        settings: ServiceSettings = ServiceSettings()) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: hostname,
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: services,
            serviceSettings: settings
        )
    }

    private func inputB(services: Set<ServiceID>,
                        settings: ServiceSettings = ServiceSettings()) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: services,
            serviceSettings: settings
        )
    }

    private func artifact(_ name: String, in bundle: GeneratedBundle) throws -> Artifact {
        try XCTUnwrap(bundle.artifacts.first { $0.fileName == name }, "missing artifact \(name)")
    }

    // MARK: - Additive services

    func testAdditiveServiceInstallsDockerAndCaddy() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.vaultwarden]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents

        XCTAssertTrue(script.contains("get.docker.com"), "Docker must be installed for additional services")
        XCTAssertTrue(script.contains("container_name: vaultwarden"), "the Vaultwarden compose file is written by the script")
        XCTAssertTrue(script.contains("vault.example.com {"), "Caddy gets a site block for Vaultwarden")
        XCTAssertTrue(script.contains("caddy-stable.list"), "Caddy must be installed from the official repository")
    }

    func testFirewallOpens443WhenCaddyIsNeeded() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("{ 80, 443 }"), "443 must open together with 80 for Caddy")
    }

    // MARK: - Firewall on Docker hosts

    func testSingleHostAndHomeRulesetsNeverDeclareAForwardChain() throws {
        for services in [Set<ServiceID>([.vaultwarden]), []] {
            let script = try artifact(
                "setup-mail-server.sh",
                in: try MailRecipe().generate(from: try inputA(services: services))
            ).contents
            XCTAssertFalse(script.contains("chain forward"),
                           "scenario A (\(services)) must not hook its own forward chain")

            let home = try artifact("setup-home-server.sh", in: try MailRecipe().generate(
                from: try inputB(services: services))).contents
            XCTAssertFalse(home.contains("chain forward"),
                           "the home node (\(services)) must not hook its own forward chain")
        }
    }

    func testEveryHostRestartsDockerAfterFirewallFlush() throws {
        for services in [Set<ServiceID>([.vaultwarden]), []] {
            let script = try artifact(
                "setup-mail-server.sh",
                in: try MailRecipe().generate(from: try inputA(services: services))
            ).contents
            XCTAssertTrue(script.contains("systemctl restart docker"),
                          "scenario A (\(services)) must restore Docker's nft rules after the flush")

            let bundle = try MailRecipe().generate(from: try inputB(services: services))
            for name in ["setup-vps.sh", "setup-home-server.sh"] {
                XCTAssertTrue(try artifact(name, in: bundle).contents
                    .contains("systemctl restart docker"),
                              "\(name) (\(services)) must restore Docker's nft rules after the flush")
            }
        }
    }

    func testEveryHostRestartsTheCrowdsecBouncerAfterFirewallFlush() throws {
        let line = "systemctl restart crowdsec-firewall-bouncer"
        for services in [Set<ServiceID>([.vaultwarden]), []] {
            let script = try artifact(
                "setup-mail-server.sh",
                in: try MailRecipe().generate(from: try inputA(services: services))
            ).contents
            XCTAssertTrue(script.contains(line),
                          "scenario A (\(services)) must put CrowdSec's tables back after the flush")

            let bundle = try MailRecipe().generate(from: try inputB(services: services))
            for name in ["setup-vps.sh", "setup-home-server.sh"] {
                XCTAssertTrue(try artifact(name, in: bundle).contents.contains(line),
                              "\(name) (\(services)) must put CrowdSec's tables back after the flush")
            }
        }
    }

    func testRelayForwardChainIssuesNoUnqualifiedDropVerdict() throws {
        for services in [Set<ServiceID>([.mailcow, .wireguardVPN]), [.vaultwarden], []] {
            let vps = try artifact("setup-vps.sh", in: try MailRecipe().generate(
                from: try inputB(services: services,
                                 settings: ServiceSettings(wireguardVPNPort: 51821)))).contents
            let chain = try forwardChainBody(ofRulesetIn: vps)
            let declaration = try XCTUnwrap(
                chain.split(separator: "\n").map(String.init)
                    .first { $0.contains("type filter hook forward") },
                "the forward chain has no hook declaration"
            )
            XCTAssertFalse(declaration.contains("policy drop"),
                           "the relay forward chain must not carry a drop policy (\(services))")
            XCTAssertTrue(declaration.contains("policy accept"),
                          "the relay forward chain declares its inverted default explicitly")
            for line in chain.split(separator: "\n").map(String.init) {
                let rule = line.trimmingCharacters(in: .whitespaces)
                guard !rule.hasPrefix("#"), rule.hasSuffix("drop") else { continue }
                XCTAssertTrue(rule.contains("iifname") || rule.contains("oifname"),
                              "drop verdict without an interface match would also drop "
                              + "Docker's traffic: \(rule)")
            }
        }
    }

    func testRelayForwardChainKeepsEveryRelayedFlowAndItsDefaultDeny() throws {
        let vps = try artifact("setup-vps.sh", in: try MailRecipe().generate(
            from: try inputB(services: [.mailcow, .wireguardVPN],
                             settings: ServiceSettings(wireguardVPNPort: 51821)))).contents
        let chain = try forwardChainBody(ofRulesetIn: vps)

        // Relayed flows.
        XCTAssertTrue(chain.contains("iifname $pub_if oifname \"wg0\" ip daddr $home_ip tcp dport"),
                      "inbound DNATed traffic to the home node")
        XCTAssertTrue(chain.contains("iifname $pub_if oifname \"wg0\" ip daddr $home_ip udp dport"),
                      "inbound DNATed UDP (the VPN protocol) to the home node")
        XCTAssertTrue(chain.contains("iifname \"wg0\" oifname \"wg0\" ip daddr $home_ip tcp dport"),
                      "hairpinned tunnel traffic to the deployment's own sites")
        XCTAssertTrue(chain.contains("iifname \"wg0\" oifname $pub_if accept"),
                      "traffic initiated by the home node")
        XCTAssertTrue(chain.contains("ct state established,related accept"))

        // Default-deny, now explicit.
        XCTAssertTrue(chain.contains("\n        iifname \"wg0\" drop"),
                      "nothing else may leave the tunnel")
        XCTAssertTrue(chain.contains("\n        oifname \"wg0\" drop"),
                      "nothing else may enter the tunnel")
        XCTAssertTrue(chain.contains("iifname $pub_if oifname $pub_if drop"),
                      "the relay must not become an open router between public interfaces")
        XCTAssertTrue(chain.contains("iifname \"wg0\" ct state invalid drop")
                      && chain.contains("oifname \"wg0\" ct state invalid drop"),
                      "invalid conntrack state stays dropped on the tunnel paths")

        let postrouting = try XCTUnwrap(vps.range(of: "chain postrouting {"))
        let nat = String(vps[postrouting.upperBound...])
        XCTAssertFalse(nat.contains("oifname \"wg0\" ip daddr $home_ip masquerade"),
                       "relayed public traffic must not be collapsed into a single tunnel source")
        let hairpin = try XCTUnwrap(nat.range(of: "snat to $hairpin_src"))
        let outboundMailMasquerade = try XCTUnwrap(nat.range(of: "oifname $pub_if ip saddr"))
        XCTAssertTrue(hairpin.lowerBound < outboundMailMasquerade.lowerBound,
                      "the hairpin SNAT must still precede the home node's outbound mail masquerade")
    }

    private func forwardChainBody(ofRulesetIn script: String) throws -> String {
        let ruleset = try XCTUnwrap(
            script.components(separatedBy: "<<'EOF_NFT'\n").dropFirst().first?
                .components(separatedBy: "\nEOF_NFT").first,
            "no nftables ruleset in the script"
        )
        let start = try XCTUnwrap(ruleset.range(of: "chain forward {"),
                                  "no forward chain in the ruleset")
        let end = try XCTUnwrap(ruleset.range(of: "\n    }", range: start.upperBound..<ruleset.endIndex),
                                "unterminated forward chain")
        return String(ruleset[start.upperBound..<end.lowerBound])
    }

    // MARK: - WireGuard VPN service

    func testVPNServiceScenarioAOpensUDPAndInstallsThePanel() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.wireguardVPN]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("udp dport { 51820 } accept"), "the VPN UDP port must be open")
        // WireGuard now runs inside the unified panel (no wg-easy).
        XCTAssertFalse(script.contains("wg-easy"), "wg-easy is replaced by the panel")
        XCTAssertTrue(script.contains("docker build -t gryonix-vpn-panel:local"))
        XCTAssertTrue(script.contains("vpn.example.com {"), "Caddy gets a site block for the VPN panel")

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("vpn.example.com."), "the VPN hostname needs an A record")
    }

    func testVPNServiceScenarioBForwardsUDPThroughTheTunnel() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: [.wireguardVPN],
            serviceSettings: ServiceSettings(wireguardVPNPort: 51821)
        )
        let bundle = try MailRecipe().generate(from: input)
        let vps = try artifact("setup-vps.sh", in: bundle).contents
        XCTAssertTrue(vps.contains("udp dport { 51821 } dnat to $home_ip"),
                      "VPN handshakes must be DNATed into the tunnel")
        XCTAssertTrue(vps.contains("ip daddr $home_ip udp dport { 51821 } accept"),
                      "the forward chain must accept the DNATed UDP flow")

        // The panel publishes the WireGuard port on the home node.
        let home = try artifact("setup-home-server.sh", in: bundle).contents
        XCTAssertTrue(home.contains("\"51821:51821/udp\""),
                      "the home node publishes the VPN port from settings")
    }

    func testVPNPortCollidingWithRelayTunnelIsRejected() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: [.wireguardVPN]
            // default wireguardVPNPort == 51820 == the relay's listen port
        )
        XCTAssertThrowsError(try MailRecipe().generate(from: input))
    }

    func testVPNPortMayStayDefaultInScenarioA() throws {
        XCTAssertNoThrow(try MailRecipe().generate(from: try inputA(services: [.wireguardVPN])))
    }

    func testAmneziaWGServiceScenarioAOpensUDPAndInstallsPanel() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.amneziaWG]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("udp dport { 51822 } accept"), "the AmneziaWG UDP port must be open")
        XCTAssertTrue(script.contains("ghcr.io/deckersu/amnezia-wg-easy:14"))
        // The unified VPN panel provides the one vpn.<domain> Caddy site.
        XCTAssertTrue(script.contains("vpn.example.com {"), "the unified VPN panel gets the Caddy site")
        XCTAssertTrue(script.contains("container_name: vpnpanel"), "the panel is installed alongside the protocol")

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("vpn.example.com."), "the VPN hostname needs an A record")
    }

    func testVPNProtocolsCoexistUnderOnePanel() throws {
        let bundle = try MailRecipe().generate(
            from: try inputA(services: [.wireguardVPN, .amneziaWG]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("udp dport { 51820, 51822 } accept"),
                      "both VPN UDP ports must be open together")
        let panelSites = script.components(separatedBy: "vpn.example.com {").count - 1
        XCTAssertEqual(panelSites, 1, "exactly one VPN Caddy site — the panel")
    }

    func testShadowsocksScenarioAOpensTCPAndUDPWithoutCaddySite() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.shadowsocks]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("8388 } accept comment \"mail + HTTP for ACME\""),
                      "Shadowsocks TCP port must be open")
        XCTAssertTrue(script.contains("udp dport { 8388 } accept"), "Shadowsocks UDP port must be open")
        XCTAssertTrue(script.contains("ghcr.io/shadowsocks/ssserver-rust:v1.24.0"))
        XCTAssertTrue(script.contains("container_name: vpnpanel"))

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("vpn.example.com."), "the VPN hostname needs an A record")
    }

    func testShadowsocksScenarioBForwardsTCPAndUDPThroughTheTunnel() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: [.shadowsocks]
        )
        let vps = try artifact("setup-vps.sh", in: try MailRecipe().generate(from: input)).contents
        XCTAssertTrue(vps.contains("8388 } dnat to $home_ip"),
                      "Shadowsocks TCP must be DNATed into the tunnel")
        XCTAssertTrue(vps.contains("udp dport { 8388 } dnat to $home_ip"),
                      "Shadowsocks UDP must be DNATed into the tunnel")
    }

    func testXrayRealityScenarioAOpensTCPPortAndKeepsKeysServerSide() throws {
        let bundle = try MailRecipe().generate(
            from: try inputA(services: [.xrayReality],
                             settings: ServiceSettings(xrayRealityPort: 8443)))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("8443 } accept"), "the Reality TCP port must be open")
        XCTAssertTrue(script.contains("ghcr.io/xtls/xray-core:26.7.11"))
        XCTAssertTrue(script.contains("docker run --rm ghcr.io/xtls/xray-core:26.7.11 x25519"),
                      "keys are generated on the server")
        XCTAssertTrue(script.contains("container_name: vpnpanel"))

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("vpn.example.com."), "the Reality endpoint needs an A record")
    }

    func testXrayRealityPortCollidingWithCaddyIsRejected() throws {
        let input = try inputA(services: [.xrayReality],
                               settings: ServiceSettings(xrayRealityPort: 443))
        XCTAssertThrowsError(try MailRecipe().generate(from: input))
    }

    func testXrayRealityDefaultPortAvoidsCaddy() throws {
        // The default must generate cleanly alongside the panel on 443.
        XCTAssertNoThrow(try MailRecipe().generate(from: try inputA(services: [.xrayReality])))
    }

    func testXrayRealityCoexistsWithWebServicesOnADistinctPort() throws {
        let input = try inputA(services: [.vaultwarden, .xrayReality],
                               settings: ServiceSettings(xrayRealityPort: 8443))
        XCTAssertNoThrow(try MailRecipe().generate(from: input))
    }

    // MARK: - Git forges

    /// Two forges, two SSH ports, one host sshd
    func testGitSSHPortCollisionsAreRejectedAndTheDefaultsCoexist() throws {
        XCTAssertNoThrow(try MailRecipe().generate(from: try inputA(services: [.forgejo, .gitlab])))

        // The host's own sshd owns 22.
        XCTAssertThrowsError(try MailRecipe().generate(
            from: try inputA(services: [.gitlab],
                             settings: ServiceSettings(gitlabSSHPort: 22))))
        XCTAssertThrowsError(try MailRecipe().generate(
            from: try inputA(services: [.forgejo, .gitlab],
                             settings: ServiceSettings(forgejoSSHPort: 2222, gitlabSSHPort: 2222))))
        XCTAssertNoThrow(try MailRecipe().generate(
            from: try inputA(services: [.forgejo, .gitlab],
                             settings: ServiceSettings(forgejoSSHPort: 0, gitlabSSHPort: 0))))
    }

    func testGitLabLandsInTheScriptBehindCaddyOnLoopback() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.gitlab]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("container_name: gitlab"))
        XCTAssertTrue(script.contains("gitlab/gitlab-ce:19.2.1-ce.0"))
        XCTAssertTrue(script.contains("git.example.com {"), "Caddy gets a site block for GitLab")
        XCTAssertTrue(script.contains(#"- "127.0.0.1:8084:80""#))
        XCTAssertTrue(script.contains("{ 80, 443, 2223 }"), "the git SSH port must be open")
        // The generated secret is substituted per line, not shared.
        XCTAssertTrue(script.contains("GITLAB_ROOT_PASSWORD=__RANDOM__"))
        XCTAssertTrue(script.contains("__RANDOM__/$(openssl rand -hex 24)"),
                      "the password is minted on the server")

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("git.example.com."), "the web UI needs an A record")
    }

    func testOpenVPNScenarioAOpensUDPAndBuildsPKIServerSide() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.openVPN]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("udp dport { 1194 } accept"), "the OpenVPN UDP port must be open")
        XCTAssertTrue(script.contains("docker build -q -t gryonix-openvpn:local"))
        XCTAssertFalse(script.contains("kylemanna"))
        XCTAssertTrue(script.contains("easyrsa --san=DNS:vpn.example.com build-server-full vpn.example.com nopass"))
        XCTAssertTrue(script.contains("OVPN_PORT=%s\\n' 'vpn.example.com' '1194'"),
                      "the client profile advertises the public endpoint")
        XCTAssertTrue(script.contains("container_name: vpnpanel"), "the unified panel is installed")

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("vpn.example.com."), "the OpenVPN endpoint needs an A record")
    }

    func testOpenVPNScenarioBForwardsUDPThroughTheTunnel() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: [.openVPN]
        )
        let vps = try artifact("setup-vps.sh", in: try MailRecipe().generate(from: input)).contents
        XCTAssertTrue(vps.contains("udp dport { 1194 } dnat to $home_ip"),
                      "OpenVPN handshakes must be DNATed into the tunnel")
    }

    func testMailcowReplacesItsDefaultAdminPasswordOverTheAPI() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertFalse(script.contains("yes |"), "yes| dies with SIGPIPE under pipefail")
        XCTAssertFalse(script.contains("mailcow-reset-admin.sh"),
                       "no password rotation — the report prints the mailcow default")
        XCTAssertTrue(script.contains(": admin\""), "the report names the admin login")
        XCTAssertTrue(script.contains("$MC_API/edit/admin"), "the install sets a new admin password over the API")
        XCTAssertTrue(script.contains("openssl rand -hex 12"), "the new password is random")
        XCTAssertTrue(script.contains(MailcowService.adminPasswordFile), "the new password is kept for the report")
        XCTAssertTrue(script.contains(": moohoo\""), "the report falls back to mailcow's default password")
    }

    func testMailcowIsRecreatedWhenTheDomainChanges() throws {
        let bundle = try MailRecipe().generate(from: try inputA(
            services: [.mailcow],
            settings: ServiceSettings(eraseMailOnDomainChange: true)))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        let guardLine = "grep -qx 'MAILCOW_HOSTNAME=mail.example.com'"
        XCTAssertTrue(script.contains(guardLine),
                      "the teardown must trigger only on a hostname mismatch")
        XCTAssertTrue(script.contains("docker compose down -v --remove-orphans"),
                      "mail data lives in the compose volumes and goes with the install")
        guard let teardown = script.range(of: guardLine),
              let clone = script.range(of: "git clone https://github.com/mailcow/mailcow-dockerized") else {
            return XCTFail("mailcow setup is missing its teardown or clone step")
        }
        XCTAssertTrue(teardown.lowerBound < clone.lowerBound,
                      "the teardown must run before the clone that it re-enables")
    }

    func testMailcowIsLeftIntactUnlessErasingWasChosen() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertFalse(script.contains("docker compose down -v --remove-orphans"),
                       "no teardown may be emitted when mail data is kept")
        XCTAssertFalse(script.contains("rm -rf \"/opt/mailcow-dockerized\""),
                       "the installation directory must not be removable by default")
        XCTAssertTrue(script.contains("/add/domain"),
                      "the new domain still has to be added to the kept installation")
    }

    func testNextcloudReappliesItsHostnameOnEveryRun() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("config:system:set trusted_domains 1 --value=files.example.com"),
                      "the current hostname must be trusted after a domain change")
        XCTAssertTrue(script.contains("config:system:set overwrite.cli.url --value=https://files.example.com"),
                      "generated links must follow the current hostname")
    }

    // MARK: - additional domains

    private func inputWithDomains(_ extra: [String], services: Set<ServiceID>) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            additionalDomains: try extra.map { try Domain($0) },
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            services: services
        )
    }

    func testAdditionalDomainsMirrorWebServicesOntoOneSite() throws {
        let bundle = try MailRecipe().generate(
            from: try inputWithDomains(["second.org"], services: [.nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("files.example.com, files.second.org {"),
                      "both names must share one site block")
        XCTAssertFalse(script.contains("\ncloud.second.org {"),
                       "a separate site would mean a separate, empty instance")
    }

    func testAdditionalDomainsBecomeMailDomains() throws {
        let bundle = try MailRecipe().generate(
            from: try inputWithDomains(["second.org"], services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("example.com\nsecond.org\nEOF_MC_DOMAINS"),
                      "both domains are fed to the provisioning loop")
        XCTAssertTrue(script.contains("$MC_API/add/dkim"), "each domain gets its own DKIM key")
    }

    func testAdditionalDomainsGetTheirOwnDNSRecords() throws {
        let bundle = try MailRecipe().generate(
            from: try inputWithDomains(["second.org"], services: [.mailcow, .nextcloud]))
        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("second.org") && dns.contains("_dmarc.second.org"),
                      "the extra mail domain needs its own DMARC record")
        XCTAssertTrue(dns.contains("files.second.org"),
                      "the mirrored service hostname needs an A record")
    }

    func testForeignServiceHostnamesAreNotMirrored() throws {
        var input = try inputWithDomains(["second.org"], services: [.nextcloud])
        input = MailRecipeInput(
            domain: input.domain, additionalDomains: input.additionalDomains,
            hostname: input.hostname, topology: input.topology, servers: input.servers,
            services: input.services,
            serviceSettings: ServiceSettings(nextcloudHostname: "files.company.net"))
        let script = try artifact("setup-mail-server.sh",
                                  in: try MailRecipe().generate(from: input)).contents
        XCTAssertTrue(script.contains("files.company.net {"), "the custom hostname is served as-is")
        XCTAssertFalse(script.contains("files.second.org"), "it must not be mirrored")
    }

    /// A BIND zone file describes exactly ONE zone
    func testEachDomainGetsItsOwnImportableFiles() throws {
        let bundle = try MailRecipe().generate(
            from: try inputWithDomains(["second.org"], services: [.mailcow, .nextcloud]))
        let names = Set(bundle.artifacts.map(\.fileName))
        XCTAssertTrue(names.contains("example.com-dns-zone.txt"))
        XCTAssertTrue(names.contains("second.org-dns-zone.txt"))
        XCTAssertTrue(names.contains("example.com-dns-records.csv"))
        XCTAssertTrue(names.contains("second.org-dns-records.csv"))

        let primary = try artifact("example.com-dns-zone.txt", in: bundle).contents
        let secondary = try artifact("second.org-dns-zone.txt", in: bundle).contents
        XCTAssertTrue(primary.contains("$ORIGIN example.com."))
        XCTAssertTrue(secondary.contains("$ORIGIN second.org."))
        func owners(_ zone: String) -> [String] {
            zone.split(separator: "\n")
                .filter { !$0.hasPrefix(";") && !$0.hasPrefix("$") && !$0.isEmpty }
                .map { String($0.split(separator: " ").first ?? "") }
        }
        XCTAssertTrue(owners(primary).allSatisfy { $0.hasSuffix("example.com.") },
                      "the primary file owns only its own names: \(owners(primary))")
        XCTAssertTrue(owners(secondary).allSatisfy { $0.hasSuffix("second.org.") },
                      "the secondary file owns only its own names: \(owners(secondary))")
        XCTAssertTrue(secondary.contains("mail.example.com."),
                      "the MX of the second domain still points at the one mail host")
        XCTAssertTrue(secondary.contains("second.org.    3600    IN MX 10"))
        XCTAssertTrue(secondary.contains("files.second.org."))
    }

    func testDuplicateAndExcessiveDomainsAreRejected() throws {
        XCTAssertThrowsError(try MailRecipe().generate(
            from: try inputWithDomains(["example.com"], services: [.mailcow])),
            "the primary domain repeated is a duplicate")
        XCTAssertThrowsError(try MailRecipe().generate(
            from: try inputWithDomains(["a.org", "a.org"], services: [.mailcow])))
        let tooMany = (1...10).map { "d\($0).org" }
        XCTAssertThrowsError(try MailRecipe().generate(
            from: try inputWithDomains(tooMany, services: [.mailcow])))
    }

    // MARK: - the per-service updater is GONE, and must stay gone

    func testNoServiceWritesAPerServiceUpdateScript() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [
            .vaultwarden, .nextcloud, .immich, .photoprism, .jellyfin, .adguardHome,
            .forgejo, .seafile, .psono, .passbolt,
        ]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertFalse(script.contains("gryonixnexus-update.sh"),
                       "the per-service updater is no longer generated")
        XCTAssertFalse(script.contains("cat > /opt/vaultwarden-update.sh"),
                       "and neither is Vaultwarden's own copy of it")
    }

    func testSecretsAreGeneratedPerLineNotShared() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("openssl rand -hex 24"))
        XCTAssertTrue(script.contains("if [ ! -f \"/opt/nextcloud/.env\" ]"), "secrets are not regenerated on a re-run")
    }

    // MARK: - Mailcow, the mail engine

    func testMailcowInstallsTheDockerizedMailStack() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents

        XCTAssertTrue(script.contains("mailcow-dockerized"))
        XCTAssertTrue(script.contains("MAILCOW_HOSTNAME=mail.example.com"))
        XCTAssertTrue(script.contains("Mailcow"), "the report must mention Mailcow")
    }

    func testDockerHostsInstallJqForMailcowScripts() throws {
        // mailcow's generate_config.sh hard-fails without jq.
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        let installLine = script.split(separator: "\n")
            .first { $0.contains("apt-get") && $0.contains(" install ") }
        XCTAssertNotNil(installLine)
        XCTAssertTrue(installLine?.contains(" jq") == true, "docker hosts must install jq")
    }

    func testMailcowConfigGenerationCannotHangOnPrompts() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains(
            "printf 'y\\ny\\ny\\n' | COMPOSE_VERSION=native MAILCOW_HOSTNAME=mail.example.com MAILCOW_TZ=UTC MAILCOW_BRANCH=master ./generate_config.sh"))
    }

    /// No occ call may be fatal or silent
    func testNextcloudOccFailuresAreLoggedNotFatal() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertFalse(script.contains(#"php occ "$@" >/dev/null 2>&1"#))
        XCTAssertTrue(script.contains(#"NC_OUT="$(docker exec -u www-data "$NC_APP" php occ "$@" 2>&1)""#))
        for key in ["trusted_domains 1", "overwriteprotocol", "overwrite.cli.url", "maintenance_window_start",
                    "background:cron", "db:add-missing-indices", "maintenance:repair"] {
            XCTAssertTrue(script.contains("could not set \(key)"),
                          "\(key) must report its own failure")
        }
        XCTAssertEqual(script.components(separatedBy: "|| log \"Nextcloud: could not set").count - 1, 7)
        XCTAssertTrue(script.contains("Nextcloud: occ did not answer"))
    }

    func testMailcowPinsTheComposeFlavourAndRepairsAnEmptyOne() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("COMPOSE_VERSION=native"))
        XCTAssertTrue(script.contains(
            "sed -i 's/^DOCKER_COMPOSE_VERSION=.*/DOCKER_COMPOSE_VERSION=native/' mailcow.conf"))
        XCTAssertTrue(script.contains("echo 'DOCKER_COMPOSE_VERSION=native' >> mailcow.conf"))
        let guardEnd = try XCTUnwrap(script.range(of: "SKIP_LETS_ENCRYPT=y/' mailcow.conf"))
        let repair = try XCTUnwrap(script.range(of: "^DOCKER_COMPOSE_VERSION="))
        XCTAssertTrue(guardEnd.upperBound < repair.lowerBound)
    }

    func testMailcowDKIMLandsInReportAndDNSPlaceholderMatchesSelector() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("$MC_API/add/dkim"))
        XCTAssertTrue(script.contains("/api/v1/get/dkim/example.com"))
        XCTAssertTrue(script.contains("dkim._domainkey.example.com"))
        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("dkim._domainkey.example.com"))
        XCTAssertFalse(dns.contains("mail._domainkey.example.com"))
    }

    func testOpenPortsSummaryFollowsTheServiceSelection() throws {
        let vpnOnly = OpenPortsSummary.entryHostPorts(for: try inputA(services: [.wireguardVPN]))
        func port(_ list: [OpenPortRequirement], _ port: Int, _ proto: OpenPortRequirement.Proto) -> OpenPortRequirement? {
            list.first { $0.port == port && $0.proto == proto }
        }
        XCTAssertNotNil(port(vpnOnly, 22, .tcp))
        XCTAssertNotNil(port(vpnOnly, 443, .tcp), "the VPN panel rides behind Caddy")
        XCTAssertNotNil(port(vpnOnly, 51820, .udp))
        XCTAssertNil(port(vpnOnly, 25, .tcp), "no mail selected — no SMTP")

        let withMailcow = OpenPortsSummary.entryHostPorts(for: try inputA(services: [.mailcow]))
        XCTAssertEqual(port(withMailcow, 25, .tcp)?.purpose, "Mailcow (SMTP)")
        XCTAssertNotNil(port(withMailcow, 4190, .tcp), "Sieve comes with mailcow")
        XCTAssertNil(port(withMailcow, 51820, .udp), "no VPN, no tunnel in scenario A")
    }

    func testAdminGuardIsImportedByEveryCaddySite() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow, .wireguardVPN]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        let importLine = "import /etc/caddy/gryonixnexus-admin-guard"
        XCTAssertEqual(script.components(separatedBy: importLine).count - 1, 2,
                       "both Caddy sites (mailcow web + panel) import the guard")
        XCTAssertTrue(script.contains("cat > /opt/gryonixnexus-admin-lockdown.sh"))
    }

    func testAdminGuardFileExistsEvenWithoutTheVPNPanel() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("[ -f /etc/caddy/gryonixnexus-admin-guard ] || : > /etc/caddy/gryonixnexus-admin-guard"),
                      "the guard snippet must exist before Caddy loads the Caddyfile")
        XCTAssertTrue(script.contains("import /etc/caddy/gryonixnexus-admin-guard"))
    }

    func testMailcowAloneStillGetsCaddyForItsOwnWebUI() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("caddy-stable.list"))
        XCTAssertTrue(script.contains("mail.example.com {"))
    }

    func testMailcowCaddyProxiesHTTPSToAvoidRedirectLoop() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("reverse_proxy https://127.0.0.1:18443"),
                      "mailcow must be proxied over HTTPS to its 18443 vhost")
        XCTAssertTrue(script.contains("tls_insecure_skip_verify"),
                      "mailcow's self-signed upstream cert must not be verified")
        XCTAssertFalse(script.contains("reverse_proxy 127.0.0.1:8080"),
                       "plain HTTP proxy to mailcow's redirect port loops")
    }

    // MARK: - Mail is optional

    func testNoMailBundleSkipsMailStackEntirely() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.vaultwarden]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents

        XCTAssertFalse(script.contains("postfix"), "without mail the mail stack is not installed")
        XCTAssertFalse(script.contains("certbot"), "service TLS is handled by Caddy, certbot is not needed")
        XCTAssertFalse(script.contains("tcp dport { 25"), "mail ports are not opened")
        XCTAssertTrue(script.contains("vault.example.com {"), "Caddy for the service is in place")
        XCTAssertTrue(script.contains("log \"REPORT\""), "the report is mandatory even without mail")

        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertFalse(dns.contains("IN MX"), "without mail there is no MX/SPF/DKIM")
        XCTAssertFalse(dns.contains("v=spf1"))
        XCTAssertTrue(dns.contains("vault.example.com."))
    }

    func testReverseDNSIsPartOfBasicSetupEvenWithoutMail() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.vaultwarden]))
        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("relay.example.com."),
                      "the default PTR target keeps its forward A record without mail")
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("relay.example.com"),
                      "the report reminds about PTR without mail too")
    }

    // MARK: - Full service configuration via the script

    func testCustomServiceHostnamesFlowEverywhere() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: [.immich],
            serviceSettings: ServiceSettings(immichHostname: "immich.example.com")
        )
        let bundle = try MailRecipe().generate(from: input)
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        let dns = try artifact("dns-records.txt", in: bundle).contents

        XCTAssertTrue(script.contains("immich.example.com {"), "Caddy proxies the user-provided domain")
        XCTAssertFalse(script.contains("photos.example.com"), "the default subdomain must not leak through")
        XCTAssertTrue(dns.contains("immich.example.com."))
    }

    func testTwoServicesAtOneHostnameRejected() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: [.nextcloud, .immich],
            serviceSettings: ServiceSettings(nextcloudHostname: "shared.example.com",
                                             immichHostname: "shared.example.com")
        )
        XCTAssertThrowsError(try MailRecipe().generate(from: input)) { error in
            guard case .inconsistentTopology(let message) = error as? ValidationError else {
                return XCTFail("expected an inconsistentTopology refusal, got \(error)")
            }
            XCTAssertTrue(message.contains("shared.example.com"), message)
        }
    }

    func testTwoServicesWithTheirOwnHostnamesAreAccepted() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: [.nextcloud, .immich],
            serviceSettings: ServiceSettings(nextcloudHostname: "cloud.example.com",
                                             immichHostname: "photos.example.com")
        )
        XCTAssertNoThrow(try MailRecipe().generate(from: input))
    }

    func testInvalidServiceHostnameRejected() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: [.nextcloud],
            serviceSettings: ServiceSettings(nextcloudHostname: "not a domain")
        )
        XCTAssertThrowsError(try MailRecipe().generate(from: input)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidHostname("not a domain"))
        }
    }

    func testReportPrintsGeneratedCredentials() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow, .vaultwarden, .nextcloud]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents

        XCTAssertTrue(script.contains("SERVICE CREDENTIALS"), "the report gathers every service's credentials")
        XCTAssertTrue(script.contains("ADMIN_TOKEN"), "the Vaultwarden token is printed from .env")
        XCTAssertTrue(script.contains("NEXTCLOUD_ADMIN_PASSWORD"), "the Nextcloud admin password is printed from .env")
        XCTAssertTrue(script.contains(": moohoo\""),
                      "the Mailcow report states the shipped default credentials")
        XCTAssertFalse(script.contains("mailcow-reset-admin.sh"),
                       "no install-time password rotation for mailcow")
    }

    func testMailcowRequiresCanonicalHostname() throws {
        let input = try inputA(services: [.mailcow], hostname: "mx.example.com")
        XCTAssertThrowsError(try MailRecipe().generate(from: input))
    }

    func testCustomHostnameAllowedWithoutMail() throws {
        let input = try inputA(services: [.vaultwarden], hostname: "mx.example.com")
        XCTAssertNoThrow(try MailRecipe().generate(from: input))
    }

    func testEmptySelectionGeneratesPanelOnlyServer() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: []))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("/etc/nftables.conf"), "the firewall is still installed")
        XCTAssertTrue(script.contains("gryonixnexus-metrics"), "the metrics collector is still installed")
        XCTAssertFalse(script.contains("docker compose"), "nothing else gets installed")
    }

    // MARK: - DNS

    func testDNSIncludesServiceSubdomains() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.vaultwarden, .nextcloud, .immich]))
        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("vault.example.com."))
        XCTAssertTrue(dns.contains("files.example.com."))
        XCTAssertTrue(dns.contains("photos.example.com."))
    }

    func testDNSHasNoDuplicateMailcowSubdomain() throws {
        let dns = try artifact("dns-records.txt",
                               in: try MailRecipe().generate(from: try inputA(services: [.mailcow]))).contents
        let aRecords = dns.split(separator: "\n")
            .filter { $0.hasPrefix("mail.example.com.") && $0.contains(" A ") }
        XCTAssertEqual(aRecords.count, 1,
                       "mail.example.com must not be duplicated by a service-catalog record")
    }

    // MARK: - Syntax

    #if os(macOS)
    func testGeneratedScriptWithAllServicesPassesBashSyntaxCheck() throws {
        let bundle = try MailRecipe().generate(from: try inputA(services: [.mailcow, .vaultwarden, .nextcloud, .immich]))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gryonixnexus-services-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", url.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "bash -n failed:\n\(errorOutput)")
    }
    #endif
}

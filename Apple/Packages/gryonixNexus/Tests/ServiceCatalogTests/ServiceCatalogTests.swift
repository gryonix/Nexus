import XCTest
@testable import ServiceCatalog

private let context = ServiceContext(domain: "example.com", sshUser: "admin")

final class PrivilegedCommandTests: XCTestCase {
    func testCommandAndSudoersDeriveFromSameFields() {
        let command = PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                        arguments: "compose -p mailcowdockerized ps")
        XCTAssertEqual(command.command, "sudo docker compose -p mailcowdockerized ps")
        XCTAssertEqual(command.sudoersLine(user: "admin"),
                       "admin ALL=(ALL) NOPASSWD: /usr/bin/docker compose -p mailcowdockerized ps")
    }

    func testEmptyArgumentsWhitelistBinaryOnly() {
        let tar = PrivilegedCommand(binaryPath: "/bin/tar", arguments: "")
        XCTAssertEqual(tar.command, "sudo tar")
        XCTAssertEqual(tar.sudoersLine(user: "admin"), "admin ALL=(ALL) NOPASSWD: /bin/tar")
    }
}

final class ServiceRegistryTests: XCTestCase {
    func testCatalogListsAllServices() {
        XCTAssertEqual(Set(ServiceRegistry.all.map(\.id)),
                       [.mailcow, .mailu, .dockerMailserver,
                        .vaultwarden, .psono, .passbolt, .nextcloud, .seafile, .immich, .jellyfin, .forgejo, .gitlab,
                        .adguardHome, .pihole, .headscale, .tailscaleNode, .cloudflared, .photoprism,
                        .homepage, .authelia,
                        .wireguardVPN, .amneziaWG, .shadowsocks, .xrayReality, .openVPN, .vpnPanel,
                        .minecraftJava, .minecraftBedrock, .craftyController,
                        .openWebUI, .ollama, .liteLLM, .anythingLLM, .qdrant, .searxng, .openclaw,
                        .n8n, .homeAssistant, .mosquitto, .zigbee2MQTT])
    }

    func testExactlyTheMembersOfExclusiveShelvesConflict() {
        let everything = Set(ServiceRegistry.all.map(\.id))
        let pairs = Set(ServiceRegistry.conflicts(in: everything).map { Set([$0.0, $0.1]) })
        var expected = Set<Set<ServiceID>>()
        for category in ServiceCategory.selectable where category.selection == .exclusive {
            let members = ServiceRegistry.services(in: category).map(\.id)
            for a in members {
                for b in members where a < b { expected.insert([a, b]) }
            }
        }
        XCTAssertFalse(expected.isEmpty, "a catalog with no exclusive shelf makes this test vacuous")
        XCTAssertEqual(pairs, expected)
        for category in ServiceCategory.selectable where category.selection == .exclusive {
            let members = Set(ServiceRegistry.services(in: category).map(\.id))
            for member in members {
                XCTAssertEqual(ServiceRegistry.service(member)?.conflicts,
                               members.subtracting([member]),
                               "\(member.rawValue) must name every other member of its shelf")
            }
        }
    }

    func testNeedsDocker() {
        XCTAssertFalse(ServiceRegistry.needsDocker([]))
        XCTAssertTrue(ServiceRegistry.needsDocker([.vaultwarden]))
    }

    func testRestartableServicesCanAlsoStartAndStop() {
        for service in ServiceRegistry.all where service.id != .wireguardVPN {
            let actions = service.actions(context)
            guard actions.restart != nil else { continue }
            XCTAssertNotNil(actions.start, "\(service.id.rawValue) can restart but not start")
            XCTAssertNotNil(actions.stop, "\(service.id.rawValue) can restart but not stop")
        }
    }

    func testStableServiceOrder() {
        let ids = ServiceRegistry.services([.immich, .mailcow]).map(\.id)
        XCTAssertEqual(ids, [.mailcow, .immich])
    }
}

final class SudoersCoverageTests: XCTestCase {
    func testEveryActionCommandIsWhitelisted() {
        for service in ServiceRegistry.all {
            let lines = service.sudoersLines(context)
            let actions = service.actions(context)

            var commands: [String] = []
            for privileged in actions.statusProbe.privilegedCommands {
                commands.append(privileged.command)
            }
            if let restart = actions.restart { commands.append(restart.privileged.command) }
            if let start = actions.start { commands.append(start.privileged.command) }
            if let stop = actions.stop { commands.append(stop.privileged.command) }

            for command in commands {
                let sudoPart = command.replacingOccurrences(of: "sudo ", with: "")
                XCTAssertTrue(
                    lines.contains { $0.hasSuffix(sudoPart) },
                    "\(service.id.rawValue): command '\(command)' has no sudoers line among \(lines)"
                )
            }
        }
    }

    func testEncryptedVolumeBackupWhitelistsChownOfFixedStagingPath() {
        let service = VaultwardenService()
        let lines = service.sudoersLines(context)
        XCTAssertTrue(lines.contains(
            "admin ALL=(ALL) NOPASSWD: /bin/chown admin /opt/backups/vaultwarden/vaultwarden-backup.tar.gz"
        ), "chown of the staging archive must be whitelisted verbatim: \(lines)")
        XCTAssertTrue(lines.contains(
            "admin ALL=(ALL) NOPASSWD: /bin/tar czf /opt/backups/vaultwarden/vaultwarden-backup.tar.gz -C / opt/vaultwarden/data"
        ), "tar must be whitelisted with its exact arguments: \(lines)")
        XCTAssertFalse(lines.contains("admin ALL=(ALL) NOPASSWD: /bin/tar"),
                       "tar must never be whitelisted with unrestricted arguments")
        XCTAssertTrue(lines.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/docker stop vaultwarden"))
        XCTAssertTrue(lines.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/docker start vaultwarden"))
    }

    func testNoSudoersWildcards() {
        // sudoers wildcards match across arguments — banned in this project.
        for service in ServiceRegistry.all {
            for line in service.sudoersLines(context) {
                XCTAssertFalse(line.contains("*"), "\(service.id.rawValue): wildcard in '\(line)'")
            }
        }
    }
}

final class ServiceDescriptionTests: XCTestCase {
    func testMailcowSetupBindsWebUIToLoopback() throws {
        let steps = MailcowService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("MAILCOW_HOSTNAME=mail.example.com"))
        XCTAssertTrue(steps.contains("HTTP_BIND=127.0.0.1"))
        XCTAssertTrue(steps.contains("SKIP_LETS_ENCRYPT=y"))
    }

    func testMailcowEnablesAPIAndProvisionsDomainWithDKIM() throws {
        let service = MailcowService()
        let steps = service.setupSteps(context).joined()
        XCTAssertTrue(steps.contains("if ! grep -q '^API_KEY=' mailcow.conf"))
        XCTAssertTrue(steps.contains(#"API_ALLOW_FROM=%s.1,127.0.0.1"#))
        XCTAssertTrue(steps.contains(#"grep '^IPV4_NETWORK=' mailcow.conf"#))
        XCTAssertTrue(steps.contains(#""${MC_NET:-172.22.1}""#))
        XCTAssertTrue(steps.contains("$MC_API/add/domain"))
        // Escaped for the shell loop that walks every mail domain.
        XCTAssertTrue(steps.contains(#"\"dkim_selector\":\"dkim\""#))
        XCTAssertTrue(steps.contains("jq -e '.domain_name'"), "domain add is guarded, not repeated")
        XCTAssertTrue(steps.contains("jq -e '.pubkey'"), "dkim add is guarded, not repeated")
        let report = service.reportSteps(context).joined()
        XCTAssertTrue(report.contains("/api/v1/get/dkim/example.com"))
        XCTAssertTrue(report.contains("dkim._domainkey.example.com"))
    }

    func testMailcowSecretsNeverRideACommandLine() {
        let service = MailcowService()
        let all = (service.setupSteps(context) + service.reportSteps(context)).joined()
        XCTAssertFalse(all.contains("-H \"X-API-Key"), "the key goes in on curl's stdin")
        XCTAssertTrue(all.contains("-K - "))
        XCTAssertTrue(all.contains("<<< \"header = \\\"X-API-Key: $MC_KEY"))
        XCTAssertFalse(all.contains("-d \"{\\\"items\\\""), "the new admin password goes in through a file")
        XCTAssertTrue(all.contains("-d @\"$MC_REQ\""))
    }

    func testMailcowAPIFailureDoesNotAbortTheInstall() throws {
        let steps = MailcowService().setupSteps(context).joined()
        XCTAssertFalse(steps.contains("curl -fsSk --max-time 20 -H \"X-API-Key: $MC_API_KEY\""),
                       "-f throws away mailcow's own error message")
        XCTAssertTrue(steps.contains("curl -sSk --max-time 20 -o \"$MC_BODY\""))
        XCTAssertTrue(steps.contains(#"-w '%{http_code}'"#), "the status is read, not inferred")
        XCTAssertTrue(steps.contains("|| log \"Mailcow"),
                      "a failed add is logged, not fatal")
        XCTAssertTrue(steps.contains("if [ \"$MC_READY\" -eq 1 ]; then"),
                      "provisioning only runs against an API that answered")
        XCTAssertTrue(steps.contains("MC_DEADLINE=$(($(date +%s) + 300))"))
        XCTAssertTrue(steps.contains("if [ \"$((MC_TRY % 6))\" -eq 0 ]; then"),
                      "the wait prints a heartbeat instead of nothing at all")
        XCTAssertTrue(steps.contains("($(mc_why))"),
                      "every diagnostic carries the status and body of the last call")
    }

    func testMailcowInstallsDKIMDumpWrapperWhitelisted() throws {
        XCTAssertEqual(MailcowService.dkimDumpScriptPath, "/opt/gryonixnexus-dkim.sh")
        XCTAssertEqual(MailcowService.dkimDumpDoneMarker, "GRYONIXNEXUS_DKIM_DONE")
        let service = MailcowService()
        let steps = service.setupSteps(context).joined()
        XCTAssertTrue(steps.contains("cat > /opt/gryonixnexus-dkim.sh"))
        XCTAssertTrue(steps.contains("chmod 750 /opt/gryonixnexus-dkim.sh"))
        XCTAssertTrue(steps.contains("$API/get/dkim/$1"), "every domain's key is read")
        XCTAssertTrue(steps.contains("$API/add/dkim"), "a missing key is created")
        XCTAssertTrue(steps.contains("$API/get/alias-domain/all"), "alias domains get keys too")
        XCTAssertTrue(steps.contains("echo \"GRYONIXNEXUS_DKIM_DONE\""))
        XCTAssertTrue(steps.contains("echo \"GRYONIXNEXUS_DKIM ${SEL:-dkim}._domainkey.$D $TXT\""))
        XCTAssertTrue(service.sudoersLines(context).contains(
            "admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-dkim.sh"
        ), "the DKIM dump wrapper must be whitelisted")
    }

    func testMailcowSyncsCaddyCertToMailDaemons() throws {
        let steps = MailcowService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("/opt/gryonixnexus-mailcow-cert-sync.sh"))
        XCTAssertTrue(steps.contains("gryonixnexus-mailcow-cert-sync.timer"))
        XCTAssertTrue(steps.contains("/var/lib/caddy/.local/share/caddy/certificates"))
        XCTAssertTrue(steps.contains("restart postfix-mailcow dovecot-mailcow nginx-mailcow"))
        XCTAssertTrue(steps.contains("data/assets/ssl"))
        let report = MailcowService().reportSteps(context).joined()
        XCTAssertFalse(report.contains("cert.pem and key.pem"),
                       "the manual copy instruction is gone — the sync is automatic")
    }

    func testMailcowExposesMailPortsOnly() {
        let ports = MailcowService().firewallPorts(context).map(\.port)
        XCTAssertEqual(Set(ports), [25, 465, 587, 143, 993, 4190])
    }

    func testComposeServicesBindToLoopbackOnly() throws {
        for service in ServiceRegistry.all {
            guard let compose = service.composeFile(context) else { continue }
            for line in compose.composeContents.split(separator: "\n") where line.contains("ports:") == false && line.contains(":80") || line.contains(":2283") {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("- \"") {
                    XCTAssertTrue(line.contains("127.0.0.1:"),
                                  "\(service.id.rawValue): public bind in '\(line)'")
                }
            }
        }
    }

    func testSecretsAreServerGeneratedMarkers() throws {
        let issuedElsewhere: Set<ServiceID> = [.cloudflared]
        for service in ServiceRegistry.all where !issuedElsewhere.contains(service.id) {
            guard let env = service.composeFile(context)?.envTemplate else { continue }
            for line in env.split(separator: "\n") where line.contains("PASSWORD") || line.contains("TOKEN") {
                XCTAssertTrue(line.hasSuffix("=__RANDOM__"),
                              "\(service.id.rawValue): secret not server-generated: '\(line)'")
            }
        }
        let tunnel = ServiceRegistry.service(.cloudflared)?.composeFile(context)?.envTemplate ?? ""
        XCTAssertEqual(tunnel.trimmingCharacters(in: .whitespacesAndNewlines), "TUNNEL_TOKEN=")
    }

    func testVaultwardenComposePinsContainerName() throws {
        let compose = try XCTUnwrap(VaultwardenService().composeFile(context))
        XCTAssertTrue(compose.composeContents.contains("container_name: vaultwarden"))
    }

    func testWebIngressHostnamesAreUniqueAmongServicesThatCanCoexist() {
        let candidates = ServiceRegistry.all.filter { !ServiceID.vpnProtocols.contains($0.id) }
        for service in candidates {
            for other in candidates where other.id != service.id
                && !service.conflicts.contains(other.id) {
                let pair = ServiceContext(domain: "example.com", sshUser: "admin",
                                          installedServices: [service.id, other.id])
                guard let a = service.webIngress(pair)?.hostname,
                      let b = other.webIngress(pair)?.hostname else { continue }
                XCTAssertNotEqual(a, b,
                                  "\(service.id.rawValue) and \(other.id.rawValue) can be installed "
                                  + "together and would fight over \(a)")
            }
        }
    }

    func testVPNProtocolsCoexistBehindTheUnifiedPanel() {
        for id in ServiceID.vpnProtocols {
            XCTAssertNil(ServiceRegistry.service(id)?.webIngress(context), "\(id.rawValue) should have no ingress")
        }
        XCTAssertEqual(VPNPanelService().webIngress(context)?.hostname, "vpn.example.com")
        XCTAssertTrue(ServiceRegistry.conflicts(in: [.wireguardVPN, .shadowsocks]).isEmpty)
        XCTAssertTrue(ServiceRegistry.conflicts(in: [.amneziaWG, .openVPN]).isEmpty)
    }

    func testDefaultHostnamesDeriveFromDomain() {
        XCTAssertEqual(VaultwardenService().webIngress(context)?.hostname, "vault.example.com")
        XCTAssertEqual(NextcloudService().webIngress(context)?.hostname, "files.example.com")
        XCTAssertEqual(ImmichService().webIngress(context)?.hostname, "photos.example.com")
        XCTAssertEqual(MailcowService().webIngress(context)?.hostname, "mail.example.com")
        // The unified VPN panel owns the VPN hostname; protocols don't.
        XCTAssertEqual(VPNPanelService().webIngress(context)?.hostname, "vpn.example.com")
        XCTAssertNil(WireGuardVPNService().webIngress(context))
    }

    // MARK: - WireGuard VPN

    func testWireGuardVPNDeclaresItsUDPPort() {
        let ports = WireGuardVPNService().firewallPorts(context)
        XCTAssertEqual(ports.map(\.port), [51820])
        XCTAssertEqual(ports.map(\.proto), [.udp])

        let custom = ServiceContext(domain: "example.com", sshUser: "admin",
                                    settings: ServiceSettings(wireguardVPNPort: 51821))
        XCTAssertEqual(WireGuardVPNService().firewallPorts(custom).map(\.port), [51821])
    }

    func testWireGuardIsAMarkerRunByThePanel() {
        let wg = WireGuardVPNService()
        XCTAssertNil(wg.composeFile(context))
        XCTAssertTrue(wg.setupSteps(context).isEmpty)
        XCTAssertNil(wg.webIngress(context))
        // The panel is the one that builds and runs WireGuard.
        let panel = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(panel.contains("docker build"))
        XCTAssertTrue(panel.contains("wireguard-tools"), "the Dockerfile carries the WG tools")
    }

    func testPanelBuildsWireGuardImageAndAuth() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("docker build -t gryonix-vpn-panel:local"))
        XCTAssertTrue(steps.contains("ADMIN_PASSWORD="), "the panel password is generated")
        XCTAssertTrue(steps.contains("10.9.0.0/24"), "the WireGuard client subnet")
        // The backend + Dockerfile are embedded and written by setup.
        XCTAssertTrue(steps.contains("wireguard-tools"), "the panel image installs the WG tools")
        XCTAssertTrue(steps.contains("/api/<proto>/clients"), "the backend exposes the client API")
        XCTAssertTrue(steps.contains("\"shadowsocks\": (ss_clients"), "Shadowsocks client management is wired")
    }

    func testPanelRotatesStalePanelPassword() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("*[!0-9a-f]* | \"\")"),
                      "a non-hex or empty stored password is regenerated")
        XCTAssertTrue(steps.contains("${#VPNPANEL_PW} -eq 24"),
                      "only a 24-hex password survives; other lengths are rotated")
        XCTAssertTrue(steps.contains("openssl rand -hex 12"),
                      "the replacement is a server-generated password")
    }

    func testFloatingImagesFollowAMajorTag() {
        XCTAssertEqual(NextcloudService.image, "nextcloud:35-apache")
        XCTAssertEqual(ImmichService.image, "ghcr.io/immich-app/immich-server:v3")
        XCTAssertEqual(ImmichService.machineLearningImage, "ghcr.io/immich-app/immich-machine-learning:v3")
        XCTAssertEqual(MailuService.cacheImage, "redis:8-alpine")
    }

    func testAmneziaPasswordHashingCannotHangTheInstall() throws {
        let steps = AmneziaWGVPNService().setupSteps(context).joined()
        XCTAssertFalse(steps.contains("$(docker run --rm ghcr.io"),
                       "an unbounded docker run is what wedged the installation")
        for call in ["timeout 60 docker run --rm -i --entrypoint node",
                     "timeout 300 docker pull"] {
            XCTAssertTrue(steps.contains(call), "unbounded call: \(call)")
        }
        XCTAssertTrue(steps.contains("PASSWORD_HASH=\\n"),
                      "without a hash the panel still starts (loopback-only, no password)")
    }

    func testAmneziaPanelPasswordNeverReachesACommandLine() throws {
        let steps = AmneziaWGVPNService().setupSteps(context).joined()
        XCTAssertFalse(steps.contains("wgpw"), "the image's tool takes the password as an argument")
        XCTAssertTrue(steps.contains(#"printf '%s' "$AWGVPN_PASSWORD" | timeout 60 docker run --rm -i"#),
                      "the password reaches the hasher on stdin")
        let dockerRuns = steps.split(separator: "\n").filter { $0.contains("docker run") }
        XCTAssertFalse(dockerRuns.isEmpty)
        for line in dockerRuns {
            let afterPipe = line.split(separator: "|", maxSplits: 1).last ?? ""
            XCTAssertFalse(afterPipe.contains("AWGVPN_PASSWORD"), "docker run must not take the password: \(line)")
        }
    }

    func testOpenVPNClientsNeverSendIPv6AroundTheTunnel() {
        let steps = OpenVPNService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("push \"block-ipv6\""))
    }

    func testPanelVPNDatapathRoutesClientTrafficOut() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("CLIENT_ALLOWED_IPS = \"0.0.0.0/0, ::/0\"\n"),
                      "IPv6 always goes into the tunnel, never around it")
        XCTAssertTrue(steps.contains("\"ip\", \"-6\", \"route\", \"replace\", \"unreachable\", \"default\""))
        XCTAssertTrue(steps.contains("SUBNET6 = \"fd09::/64\""))
        XCTAssertTrue(steps.contains("CLIENT_MTU = 1280"),
                      "the MTU has to survive double encapsulation")
        XCTAssertTrue(steps.contains("def wan_if"), "the WAN interface is detected, not assumed")
        XCTAssertFalse(steps.contains("-o eth0 -j MASQUERADE"),
                       "NAT must not be pinned to a hard-coded interface")
        XCTAssertTrue(steps.contains("--clamp-mss-to-pmtu"), "large TCP segments need clamping")
        XCTAssertTrue(steps.contains("net.ipv4.ip_forward=1"),
                      "routing between the tunnel and the WAN needs forwarding on")
        XCTAssertTrue(steps.contains("def wg_apply_nat"),
                      "NAT is applied outside wg-quick, not in a PostUp hook")
        XCTAssertFalse(steps.contains("PostUp = iptables"),
                       "a failing PostUp firewall hook must not tear the tunnel down")
    }

    /// Accounts with roles
    func testPanelManagesAccountsWithRoles() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("def ensure_superadmin"), "the setup password bootstraps an account")
        XCTAssertTrue(steps.contains("hashlib.pbkdf2_hmac"), "passwords are hashed, never stored")
        XCTAssertTrue(steps.contains("def require_admin"), "account management is gated by role")
        XCTAssertTrue(steps.contains("The main administrator cannot be removed."))
        XCTAssertTrue(steps.contains("Only the main administrator can change this account."))
        XCTAssertTrue(steps.contains(#"request.method not in ("GET", "HEAD", "OPTIONS")"#),
                      "the CSRF guard must cover PATCH, not just POST/DELETE")
        XCTAssertFalse(steps.contains(#"request.method in ("POST", "DELETE")"#),
                       "the narrow verb list left PATCH unguarded")
    }

    /// Password recovery
    func testPanelSendsPasswordResetMail() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("COPY reset.html /app/reset.html"))
        XCTAssertTrue(steps.contains("EOF_VPNPANEL_RESET"), "the reset page is written to the server")
        XCTAssertTrue(steps.contains("def issue_reset") && steps.contains("def consume_reset"))
        XCTAssertTrue(steps.contains("hashlib.sha256((token or \"\").encode()"),
                      "reset tokens are stored hashed, like passwords")
        XCTAssertTrue(steps.contains("def mailcow_mailboxes"), "mailcow's mailboxes are offered as senders")

        let compose = try XCTUnwrap(VPNPanelService().composeFile(context)).composeContents
        XCTAssertTrue(compose.contains("/opt/mailcow-dockerized:/protocols/mailcow:ro"),
                      "the directory is mounted, never mailcow.conf itself")
        XCTAssertFalse(compose.contains("mailcow.conf:/protocols"),
                       "binding the file would have docker create it and break a later mailcow install")
        XCTAssertTrue(compose.contains("host.docker.internal:host-gateway"),
                      "the panel reaches the host's SMTP listener through the gateway")
    }

    func testPanelUsesFormLoginSessionAuthAndLocalizedUI() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("COPY login.html /app/login.html"))
        XCTAssertTrue(steps.contains("cat > /opt/gryonix-vpn-panel/build/login.html"))
        XCTAssertTrue(steps.contains("def login_submit"))
        XCTAssertFalse(steps.contains("WWW-Authenticate"), "the Basic-auth prompt is gone")
        // H3: session cookie auth, hardened — secure cookie + brute-force throttle.
        XCTAssertTrue(steps.contains("SESSION_COOKIE_SECURE=True"))
        XCTAssertTrue(steps.contains("def rate_limited"))
        XCTAssertTrue(steps.contains("def ensure_secret"))
        // H2: the frontend ships the shared translation dictionary.
        XCTAssertTrue(steps.contains("function t(k)"))
        XCTAssertTrue(steps.contains("VPN-сервисы"), "the Russian strings are present")
    }

    func testPanelComposeUpRunsFromItsOwnDirectory() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        let cd = try XCTUnwrap(steps.range(of: "cd \(VPNPanelService.path)\n"))
        let up = try XCTUnwrap(steps.range(of: "docker compose -p vpnpanel up -d"))
        XCTAssertTrue(cd.lowerBound < up.lowerBound, "cd must precede compose up")
    }

    func testPanelInstallsAdminLockdownSwitch() throws {
        XCTAssertEqual(VPNPanelService.lockdownScriptPath, "/opt/gryonixnexus-admin-lockdown.sh")
        let steps = VPNPanelService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("cat > /opt/gryonixnexus-admin-lockdown.sh"))
        XCTAssertTrue(steps.contains("if [ -f /etc/caddy/gryonixnexus-admin-guard ]; then"),
                      "guard is created and locked once on first install; re-runs keep the current state")
        XCTAssertTrue(steps.contains("/opt/gryonixnexus-admin-lockdown.sh on"),
                      "first install must ship the guard locked, not public")
        XCTAssertTrue(steps.contains("printf '@gryonixnexus_relay {\\n'"))
        XCTAssertTrue(steps.contains("printf '    remote_ip 10.8.0.0/24\\n'"))
        XCTAssertTrue(steps.contains("printf '    not remote_ip 10.8.0.254/32\\n'"),
                      "the hairpin source is excluded from the relay ban")
        XCTAssertTrue(steps.contains("printf '@gryonixnexus_public not remote_ip private_ranges %s\\n' \"$selfip\""))
        XCTAssertTrue(steps.contains("ip -4 -o addr show scope global"),
                      "the guard must learn the host's own public IPs for the hairpin allow")
        XCTAssertTrue(steps.contains("not remote_ip private_ranges %s\\n' \"$selfip\""),
                      "the host's own public IPs join the private-range allow-list")
        XCTAssertTrue(steps.contains("printf '@gryonixnexus_tunnel header Cf-Connecting-IP *\\n'"),
                      "tunnel visitors arrive from loopback and must stay outside")
        XCTAssertTrue(steps.contains("printf '    header Cf-Connecting-IP *\\n'"))
        XCTAssertTrue(steps.contains("only)"))
        XCTAssertTrue(steps.contains("printf '    host %s\\n' \"$hosts\""))
        XCTAssertTrue(steps.contains(#"*[!A-Za-z0-9.-]*|"") echo "invalid host: $h""#))
        let relayIndex = steps.range(of: "@gryonixnexus_relay")?.lowerBound
        let publicIndex = steps.range(of: "@gryonixnexus_public")?.lowerBound
        if let relayIndex, let publicIndex {
            XCTAssertLessThan(relayIndex, publicIndex,
                              "relay deny must come before the private-range allow")
        } else {
            XCTFail("guard matchers missing from the wrapper")
        }
        XCTAssertEqual(VPNPanelService().webIngress(context)?.adminGuard, true)
        let sudoers = VPNPanelService().sudoersLines(context)
        XCTAssertTrue(sudoers.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-admin-lockdown.sh"),
                      "missing the args-free lockdown sudoers entry")
        XCTAssertFalse(sudoers.joined().contains("gryonixnexus-admin-lockdown.sh on"),
                       "per-verb entries are gone — one args-free line covers all verbs")
    }

    func testPanelManagesEveryProtocolAndMountsTheirConfigs() throws {
        let steps = VPNPanelService().setupSteps(context).joined()
        // All five protocols are wired into the generic client-CRUD registry.
        for handler in ["\"wireguard\": (wg_clients", "\"shadowsocks\": (ss_clients",
                        "\"xray\": (xr_clients", "\"openvpn\": (ov_clients",
                        "\"amneziawg\": (awg_clients"] {
            XCTAssertTrue(steps.contains(handler), "missing handler registration: \(handler)")
        }
        for op in ["openvpn_build", "openvpn_profile", "openvpn_revoke"] {
            XCTAssertTrue(steps.contains("broker_ok(\"\(op)\""), "OpenVPN goes through the agent's broker: \(op)")
        }
        // The panel sees each protocol's config dir under /protocols/*.
        let compose = try XCTUnwrap(VPNPanelService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("/opt/shadowsocks:/protocols/shadowsocks"))
        XCTAssertTrue(compose.contains("/opt/xray:/protocols/xray"))
        XCTAssertTrue(compose.contains("/opt/openvpn/data:/protocols/openvpn"))
        XCTAssertTrue(compose.contains("/opt/awgvpn/data:/protocols/amneziawg"))
    }

    func testAdminUsernameThreadsInAndPasswordsAreServerGenerated() throws {
        let custom = ServiceContext(
            domain: "example.com", sshUser: "admin",
            settings: ServiceSettings(adminUsername: "owner"))
        let panel = VPNPanelService().setupSteps(custom).joined()
        XCTAssertTrue(panel.contains(#"printf 'ADMIN_USER=%s\n' 'owner'"#))
        XCTAssertTrue(panel.contains("openssl rand -hex 12"),
                      "the panel password is generated on the server")
        let nc = try XCTUnwrap(NextcloudService().composeFile(custom))
        XCTAssertTrue(nc.composeContents.contains("NEXTCLOUD_ADMIN_USER: owner"))
        XCTAssertTrue(nc.envTemplate?.contains("NEXTCLOUD_ADMIN_PASSWORD=__RANDOM__") == true,
                      "the Nextcloud admin password is generated on the server")
        XCTAssertFalse(NextcloudService().setupSteps(custom).joined()
            .contains("occ user:resetpassword"), "no password forcing on re-runs")

        // The report labels the password as generated on the server.
        XCTAssertTrue(VPNPanelService().reportSteps(custom).joined()
            .contains(L10nServices.passwordGeneratedOnServerLabel(.en)))
        XCTAssertTrue(NextcloudService().reportSteps(custom).joined()
            .contains(L10nServices.passwordGeneratedOnServerLabel(.en)))

        XCTAssertEqual(ServiceContext(domain: "example.com", sshUser: "admin")
            .settings.adminUsername, "admin")
    }

    // MARK: - AmneziaWG VPN

    func testAmneziaWGDeclaresDistinctPortsAndSubnet() throws {
        let service = AmneziaWGVPNService()
        XCTAssertEqual(service.firewallPorts(context).map(\.port), [51822])
        XCTAssertEqual(service.firewallPorts(context).map(\.proto), [.udp])
        XCTAssertNil(service.webIngress(context), "the unified panel owns the ingress")

        let compose = try XCTUnwrap(service.composeFile(context)?.composeContents)
        // DeckerSU build: real multi-arch (w0rng's arm variants carry amd64 binaries).
        XCTAssertTrue(compose.contains("ghcr.io/deckersu/amnezia-wg-easy:14"))
        XCTAssertTrue(compose.contains("\"51822:51822/udp\""))
        XCTAssertTrue(compose.contains("127.0.0.1:51823:51823"))
        XCTAssertTrue(compose.contains("WG_DEFAULT_ADDRESS: 10.10.0.x"))
        XCTAssertTrue(compose.contains("container_name: awgvpn"))
        XCTAssertTrue(compose.contains("/data:/etc/amnezia/amneziawg"))
        XCTAssertFalse(compose.contains(":/etc/wireguard"))
        XCTAssertTrue(compose.contains("/dev/net/tun:/dev/net/tun"))
    }

    func testAmneziaWGSetupGeneratesPasswordOnceAndReportsIt() {
        let steps = AmneziaWGVPNService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("if [ ! -f .env ]"))
        XCTAssertTrue(steps.contains("bcryptjs"))
        XCTAssertTrue(steps.contains("chmod 600 .env"))
        XCTAssertTrue(steps.contains(#"sed -i '/^PASSWORD_HASH=/s/\$\{1,\}/$$/g' .env"#))
        let report = AmneziaWGVPNService().reportSteps(context).joined()
        XCTAssertFalse(report.contains("ADMIN_PASSWORD"))
        XCTAssertTrue(report.contains(L10nServices.amneziaAdminViaWireGuardNote(context.language)))
        XCTAssertTrue(report.contains("WireGuard"))
    }

    // MARK: - Shadowsocks

    func testShadowsocksDeclaresTCPandUDPButNoIngress() throws {
        let service = ShadowsocksService()
        let ports = service.firewallPorts(context)
        XCTAssertEqual(ports.map(\.port), [8388, 8388])
        XCTAssertEqual(Set(ports.map(\.proto)), [.tcp, .udp])
        XCTAssertNil(service.webIngress(context))
        XCTAssertEqual(service.dnsHostnames(context), ["vpn.example.com"])
    }

    func testShadowsocksGeneratesKeyAndReportsSIP002Link() {
        let steps = ShadowsocksService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("if [ ! -f config.json ]"), "re-runs must keep the key")
        XCTAssertTrue(steps.contains("openssl rand -base64 32"), "AEAD-2022 needs a 32-byte key")
        XCTAssertTrue(steps.contains("2022-blake3-aes-256-gcm"))
        XCTAssertTrue(steps.contains("chmod 600 config.json"))

        let report = ShadowsocksService().reportSteps(context).joined()
        XCTAssertTrue(report.contains("ss://2022-blake3-aes-256-gcm:${SS_ENC}@vpn.example.com:8388#gryonixNexus"))
        // The base64 key's +,/,= are percent-encoded for the URL.
        XCTAssertTrue(report.contains("s/+/%2B/g"))
    }

    func testShadowsocksComposeRunsWithoutCaddy() throws {
        let compose = try XCTUnwrap(ShadowsocksService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("ghcr.io/shadowsocks/ssserver-rust:v1.24.0"))
        XCTAssertTrue(compose.contains("\"8388:8388/tcp\""))
        XCTAssertTrue(compose.contains("\"8388:8388/udp\""))
        XCTAssertTrue(compose.contains("container_name: shadowsocks"))
        XCTAssertTrue(compose.contains("command: ssserver -c /etc/shadowsocks-rust/config.json"))
        XCTAssertTrue(compose.contains(#"user: "0:0""#))
    }

    // MARK: - Xray VLESS/Reality

    func testXrayRealityDeclaresTCPOnlyAndNoIngress() throws {
        let service = XrayRealityService()
        let ports = service.firewallPorts(context)
        XCTAssertEqual(ports.map(\.port), [8443])
        XCTAssertEqual(ports.map(\.proto), [.tcp])
        XCTAssertNil(service.webIngress(context))
        XCTAssertEqual(service.dnsHostnames(context), ["vpn.example.com"])
    }

    func testXrayRealityGeneratesKeysAndReportsVlessLink() {
        let steps = XrayRealityService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("if [ ! -f config/config.json ]"), "re-runs keep keys")
        XCTAssertTrue(steps.contains("docker run --rm ghcr.io/xtls/xray-core:26.7.11 uuid"))
        XCTAssertTrue(steps.contains("docker run --rm ghcr.io/xtls/xray-core:26.7.11 x25519"))
        XCTAssertTrue(steps.contains("s/^PrivateKey:"))
        XCTAssertTrue(steps.contains("s/^Password[^:]*:"))
        XCTAssertTrue(steps.contains("s/^Public key:"))
        XCTAssertTrue(steps.contains("openssl rand -hex 8"), "shortId")
        XCTAssertTrue(steps.contains("xtls-rprx-vision"))
        XCTAssertTrue(steps.contains("\"serverNames\": [ \"www.apple.com\" ]"))
        // The vless:// link is persisted for the report.
        XCTAssertTrue(steps.contains("vless://%s@%s:%s"))
        let report = XrayRealityService().reportSteps(context).joined()
        XCTAssertTrue(report.contains("cat /opt/xray/link.txt"))
    }

    func testXrayRealityComposeMountsConfdirTCPOnly() throws {
        let compose = try XCTUnwrap(XrayRealityService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("ghcr.io/xtls/xray-core:26.7.11"))
        XCTAssertTrue(compose.contains("/usr/local/etc/xray:ro"))
        XCTAssertTrue(compose.contains("\"8443:8443/tcp\""))
        XCTAssertFalse(compose.contains("/udp"), "Reality is TCP-only")
        XCTAssertTrue(compose.contains("container_name: xray"))
        XCTAssertTrue(compose.contains(#"user: "0:0""#))
    }

    // MARK: - OpenVPN

    func testOpenVPNDeclaresUDPOnlyAndNoIngress() {
        let service = OpenVPNService()
        XCTAssertEqual(service.firewallPorts(context).map(\.port), [1194])
        XCTAssertEqual(service.firewallPorts(context).map(\.proto), [.udp])
        XCTAssertNil(service.webIngress(context))
        XCTAssertEqual(service.dnsHostnames(context), ["vpn.example.com"])
    }

    func testOpenVPNBuildsPKINonInteractivelyAndInlinesProfile() {
        let steps = OpenVPNService().setupSteps(context).joined()
        XCTAssertTrue(steps.contains("if [ ! -f data/pki/ca.crt ]"), "re-runs keep the PKI")
        XCTAssertTrue(steps.contains("FROM alpine:3.22"))
        XCTAssertTrue(steps.contains("EASYRSA_BATCH=1"))
        XCTAssertTrue(steps.contains("EASYRSA_ALGO=ec"))
        XCTAssertTrue(steps.contains("docker build -q -t gryonix-openvpn:local"))
        XCTAssertTrue(steps.contains("easyrsa init-pki"))
        XCTAssertTrue(steps.contains("easyrsa build-ca nopass"))
        XCTAssertTrue(steps.contains("easyrsa build-client-full gryonixnexus nopass"))
        XCTAssertTrue(steps.contains("openvpn --genkey secret /etc/openvpn/tc.key"))
        XCTAssertTrue(steps.contains("ovpn_getclient gryonixnexus > /opt/openvpn/gryonixnexus.ovpn"))
        XCTAssertTrue(steps.contains("COPY ovpn_getclient ovpn_revokeclient gryonix-ovpn-run /usr/local/bin/"))
        let report = OpenVPNService().reportSteps(context).joined()
        XCTAssertTrue(report.contains("cat /opt/openvpn/gryonixnexus.ovpn"), "the profile is inlined in the report")
    }

    func testOpenVPNComposeNeedsTunAndNetAdmin() throws {
        let compose = try XCTUnwrap(OpenVPNService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("gryonix-openvpn:local"))
        XCTAssertTrue(compose.contains("- NET_ADMIN"))
        XCTAssertTrue(compose.contains("/dev/net/tun"))
        XCTAssertTrue(compose.contains("net.ipv4.ip_forward=1"))
        XCTAssertTrue(compose.contains("\"1194:1194/udp\""))
        XCTAssertTrue(compose.contains("container_name: openvpn"))
    }

    func testCustomHostnamesOverrideDefaults() {
        let custom = ServiceContext(domain: "example.com", sshUser: "admin",
                                    settings: ServiceSettings(vaultwardenHostname: "pass.custom.dev",
                                                              nextcloudHostname: "files.custom.dev",
                                                              immichHostname: "pics.custom.dev",
                                                              forgejoHostname: "code.custom.dev",
                                                              gitlabHostname: "forge.custom.dev"))
        XCTAssertEqual(VaultwardenService().webIngress(custom)?.hostname, "pass.custom.dev")
        XCTAssertEqual(NextcloudService().dnsHostnames(custom), ["files.custom.dev"])
        XCTAssertEqual(ImmichService().dnsHostnames(custom), ["pics.custom.dev"])
        XCTAssertEqual(ForgejoService().dnsHostnames(custom), ["code.custom.dev"])
        XCTAssertEqual(GitLabService().dnsHostnames(custom), ["forge.custom.dev"])
        let gitlab = GitLabService().composeFile(custom)?.composeContents ?? ""
        XCTAssertTrue(gitlab.contains("external_url 'https://forge.custom.dev'"))
        // The custom hostname flows into the service's own config too.
        let compose = VaultwardenService().composeFile(custom)?.composeContents ?? ""
        XCTAssertTrue(compose.contains("https://pass.custom.dev"))
    }

    func testServicesAreFullyConfiguredBySetup() throws {
        let nextcloud = try XCTUnwrap(NextcloudService().composeFile(context)?.composeContents)
        XCTAssertTrue(nextcloud.contains("NEXTCLOUD_ADMIN_USER: admin"))
        XCTAssertTrue(nextcloud.contains("NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}"))
        XCTAssertFalse(nextcloud.contains("OVERWRITEHOST"), "links follow the name the request used")
        XCTAssertTrue(nextcloud.contains("TRUSTED_PROXIES: 127.0.0.1 172.16.0.0/12 192.168.0.0/16"), "Caddy's forwarded address is believed")
        XCTAssertTrue(nextcloud.contains("entrypoint: /cron.sh"), "background jobs run")

        let vaultwarden = try XCTUnwrap(VaultwardenService().composeFile(context)?.composeContents)
        XCTAssertTrue(vaultwarden.contains("ADMIN_TOKEN: ${ADMIN_TOKEN}"))
        XCTAssertTrue(vaultwarden.contains("SIGNUPS_ALLOWED: \"false\""), "a password manager starts closed")

        let mailcowSetup = MailcowService().setupSteps(context).joined()
        XCTAssertFalse(mailcowSetup.contains("mailcow-reset-admin.sh"),
                       "no install-time password rotation for mailcow")
        let mailcowReport = MailcowService().reportSteps(context).joined()
        XCTAssertTrue(mailcowReport.contains(": admin\""))
        XCTAssertTrue(mailcowReport.contains(": moohoo\""))

        for service in ServiceRegistry.services([.mailcow, .vaultwarden, .nextcloud, .immich,
                                                 .forgejo, .gitlab]) {
            XCTAssertFalse(service.reportSteps(context).isEmpty,
                           "\(service.id.rawValue): the report must print the service credentials")
        }
    }

    func testVaultwardenSignupsToggle() throws {
        let closed = ServiceContext(domain: "example.com", sshUser: "admin",
                                    settings: ServiceSettings(vaultwardenAllowSignups: false))
        let closedCompose = try XCTUnwrap(VaultwardenService().composeFile(closed)?.composeContents)
        XCTAssertTrue(closedCompose.contains("SIGNUPS_ALLOWED: \"false\""))

        let open = ServiceContext(domain: "example.com", sshUser: "admin",
                                  settings: ServiceSettings(vaultwardenAllowSignups: true))
        let compose = try XCTUnwrap(VaultwardenService().composeFile(open)?.composeContents)
        XCTAssertTrue(compose.contains("SIGNUPS_ALLOWED: \"true\""))
    }

    func testVaultwardenSignupsToggleOverridesAdminPanelConfig() throws {
        for (allow, literal) in [(true, "true"), (false, "false")] {
            let context = ServiceContext(domain: "example.com", sshUser: "admin",
                                         settings: ServiceSettings(vaultwardenAllowSignups: allow))
            let setup = VaultwardenService().setupSteps(context).joined()
            XCTAssertTrue(setup.contains(".signups_allowed == \(literal)"),
                          "config.json must be checked against the requested toggle")
            XCTAssertTrue(setup.contains(".signups_allowed = \(literal)"),
                          "a mismatching config.json must be rewritten")
            XCTAssertTrue(setup.contains("docker restart vaultwarden"),
                          "config.json is read at startup — a change needs a restart")
        }
    }

    func testVaultwardenSyncsStoredDomainOnReinstall() {
        let context = ServiceContext(domain: "example.com", sshUser: "admin",
                                     settings: ServiceSettings())
        let setup = VaultwardenService().setupSteps(context).joined()
        XCTAssertTrue(setup.contains("VW_DOMAIN=\"https://vault.example.com\""),
                      "the current hostname is what config.json must be synced to")
        XCTAssertTrue(setup.contains("(.domain // $d) == $d"),
                      "an absent domain key must not count as a mismatch")
        XCTAssertTrue(setup.contains("if has(\"domain\") then .domain = $d else . end"),
                      "the key must be rewritten in place, never added")
    }

    func testVaultwardenReportExplainsSelfRegistration() {
        let report = VaultwardenService().reportSteps(context).joined()
        XCTAssertTrue(report.contains("create your own account"),
                      "the report must spell out that the user registers their own account")
    }

    // MARK: - Forgejo

    func testForgejoLeavesNoWebInstallerAndCreatesItsAdmin() throws {
        let compose = try XCTUnwrap(ForgejoService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains(#"FORGEJO__security__INSTALL_LOCK: "true""#))
        XCTAssertTrue(compose.contains("FORGEJO__database__DB_TYPE: postgres"))
        XCTAssertTrue(compose.contains("FORGEJO__server__ROOT_URL: https://git.example.com/"))
        // Closed registration is only safe because the admin is provisioned.
        XCTAssertTrue(compose.contains(#"FORGEJO__service__DISABLE_REGISTRATION: "true""#))

        let setup = ForgejoService().setupSteps(context).joined()
        XCTAssertTrue(setup.contains("forgejo admin user create --admin --username admin-gryonix"))
        XCTAssertTrue(setup.contains("FORGEJO_ADMIN_PASSWORD"))
        XCTAssertTrue(setup.contains("grep -cE '^[0-9]+[[:space:]]+admin-gryonix[[:space:]]'"))
    }

    func testForgejoRefusesToAskForAReservedAdministratorName() {
        let reserved = ServiceContext(domain: "example.com", sshUser: "admin",
                                      settings: ServiceSettings(adminUsername: "admin"))
        XCTAssertEqual(ForgejoService().adminUsername(reserved), "admin-gryonix")
        XCTAssertTrue(ForgejoService().reportSteps(reserved).joined().contains("admin-gryonix"))

        let free = ServiceContext(domain: "example.com", sshUser: "admin",
                                  settings: ServiceSettings(adminUsername: "morgan"))
        XCTAssertEqual(ForgejoService().adminUsername(free), "morgan")
        XCTAssertTrue(ForgejoService().setupSteps(free).joined()
            .contains("--username morgan "))
    }

    func testForgejoAdminStepIsNeverFatalAndKeepsItsOutput() {
        let setup = ForgejoService().setupSteps(context).joined()
        XCTAssertFalse(setup.contains(">/dev/null 2>&1"),
                       "the reason a call failed is the only thing that explains it")
        XCTAssertTrue(setup.contains("|| log "), "a failed admin creation must log, not abort")
        XCTAssertTrue(setup.contains("FJ_DEADLINE"),
                      "waiting must be bounded by a deadline, not a number of tries")
        XCTAssertTrue(setup.contains("timeout 120 docker exec"))
    }

    func testForgejoSSHPortIsOptionalAndNeverTakesPort22() throws {
        let onPort = ServiceContext(domain: "example.com", sshUser: "admin",
                                    settings: ServiceSettings(forgejoSSHPort: 2222))
        let onCompose = try XCTUnwrap(ForgejoService().composeFile(onPort)?.composeContents)
        XCTAssertTrue(onCompose.contains(#"FORGEJO__server__START_SSH_SERVER: "false""#))
        XCTAssertFalse(onCompose.contains(#"FORGEJO__server__START_SSH_SERVER: "true""#))
        XCTAssertTrue(onCompose.contains(#"FORGEJO__server__SSH_PORT: "2222""#))
        XCTAssertTrue(onCompose.contains(#"FORGEJO__server__SSH_LISTEN_PORT: "22""#))
        XCTAssertTrue(onCompose.contains(#"- "2222:22""#))
        XCTAssertEqual(ForgejoService().firewallPorts(onPort).map(\.port), [2222])

        let off = ServiceContext(domain: "example.com", sshUser: "admin",
                                 settings: ServiceSettings(forgejoSSHPort: 0))
        let offCompose = try XCTUnwrap(ForgejoService().composeFile(off)?.composeContents)
        XCTAssertTrue(offCompose.contains(#"FORGEJO__server__START_SSH_SERVER: "false""#))
        XCTAssertFalse(offCompose.contains(":22\""), "nothing may be published when SSH is off")
        XCTAssertTrue(ForgejoService().firewallPorts(off).isEmpty,
                      "a disabled SSH server must not open a firewall port")

        XCTAssertNotEqual(ServiceSettings().forgejoSSHPort, 22)
    }

    func testForgejoWebUIBindsToLoopbackOnly() throws {
        let compose = try XCTUnwrap(ForgejoService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains(#"- "127.0.0.1:8083:3000""#))
        XCTAssertEqual(ForgejoService().webIngress(context)?.hostname, "git.example.com")
        XCTAssertEqual(ForgejoService().webIngress(context)?.adminGuard, true)
    }

    // MARK: - GitLab

    func testGitLabProvisionsItsRootAccountAndClosesSignup() throws {
        let compose = try XCTUnwrap(GitLabService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("gitlab_rails['initial_root_password'] = ENV['GITLAB_ROOT_PASSWORD']"))
        XCTAssertTrue(compose.contains("GITLAB_ROOT_PASSWORD: ${GITLAB_ROOT_PASSWORD}"))
        XCTAssertEqual(try XCTUnwrap(GitLabService().composeFile(context)?.envTemplate)
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       "GITLAB_ROOT_PASSWORD=__RANDOM__")
        XCTAssertTrue(compose.contains("gitlab_rails['store_initial_root_password'] = false"))

        let setup = GitLabService().setupSteps(context).joined()
        XCTAssertTrue(setup.contains("ApplicationSetting.last.update!(signup_enabled: false)"))
        XCTAssertTrue(setup.contains("/opt/gitlab-ce/.gryonixnexus-signup-closed"))

        let report = GitLabService().reportSteps(context).joined()
        XCTAssertTrue(report.contains("grep '^GITLAB_ROOT_PASSWORD=' /opt/gitlab-ce/.env"),
                      "the report is the only place the generated password is written down")
        XCTAssertTrue(report.contains(": root\""), "GitLab names its administrator, we do not")
    }

    func testGitLabFirstBootWaitIsNeverFatalAndKeepsItsOutput() {
        let setup = GitLabService().setupSteps(context).joined()
        XCTAssertFalse(setup.contains(">/dev/null 2>&1"),
                       "the reason a call failed is the only thing that explains it")
        XCTAssertTrue(setup.contains("|| log ") || setup.contains("else\n      log "),
                      "a failed step must log, not abort")
        XCTAssertTrue(setup.contains("GL_DEADLINE"),
                      "waiting must be bounded by a deadline, not a number of tries")
        XCTAssertTrue(setup.contains(#"timeout "$GL_TIMEOUT" docker exec"#))
        XCTAssertTrue(setup.contains("GL_TIMEOUT=300"))
    }

    func testGitLabServesPlainHTTPOnLoopbackAndNeverRunsItsOwnACME() throws {
        let compose = try XCTUnwrap(GitLabService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("external_url 'https://git.example.com'"))
        XCTAssertTrue(compose.contains("nginx['listen_port'] = 80"))
        XCTAssertTrue(compose.contains("nginx['listen_https'] = false"))
        XCTAssertTrue(compose.contains("letsencrypt['enable'] = false"))
        XCTAssertTrue(compose.contains(#"- "127.0.0.1:8084:80""#))
        XCTAssertEqual(GitLabService().webIngress(context)?.hostname, "git.example.com")
        XCTAssertEqual(GitLabService().webIngress(context)?.adminGuard, true)
    }

    /// Git-over-SSH is the one public bind GitLab asks for
    func testGitLabSSHPortIsOptionalAndClearsForgejoAndTheHostSSHD() throws {
        let onPort = ServiceContext(domain: "example.com", sshUser: "admin",
                                    settings: ServiceSettings(gitlabSSHPort: 2223))
        let onCompose = try XCTUnwrap(GitLabService().composeFile(onPort)?.composeContents)
        XCTAssertTrue(onCompose.contains("gitlab_rails['gitlab_shell_ssh_port'] = 2223"))
        XCTAssertTrue(onCompose.contains(#"- "2223:22""#))
        XCTAssertEqual(GitLabService().firewallPorts(onPort).map(\.port), [2223])

        let off = ServiceContext(domain: "example.com", sshUser: "admin",
                                 settings: ServiceSettings(gitlabSSHPort: 0))
        let offCompose = try XCTUnwrap(GitLabService().composeFile(off)?.composeContents)
        XCTAssertFalse(offCompose.contains(":22\""), "nothing may be published when SSH is off")
        XCTAssertFalse(offCompose.contains("gitlab_shell_ssh_port"),
                       "no clone URL may advertise a port that is not published")
        XCTAssertTrue(GitLabService().firewallPorts(off).isEmpty,
                      "a disabled SSH server must not open a firewall port")

        XCTAssertNotEqual(ServiceSettings().gitlabSSHPort, 22)
        XCTAssertNotEqual(ServiceSettings().gitlabSSHPort, ServiceSettings().forgejoSSHPort)
    }

    func testGitLabKeepsAllItsStateUnderTheDirectoryUninstallRemoves() throws {
        let compose = try XCTUnwrap(GitLabService().composeFile(context))
        let spec = GitLabService().uninstallSpec(context)
        XCTAssertEqual(spec.configDirectory, compose.directory)
        XCTAssertEqual(spec.composeProject, "gitlab")
        let volumeLines = compose.composeContents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") && $0.contains(":/") && !$0.contains("127.0.0.1") }
        for mount in ["/etc/gitlab", "/var/log/gitlab", "/var/opt/gitlab"] {
            let line = try XCTUnwrap(volumeLines.first { $0.hasSuffix(":\(mount)") },
                                     "\(mount) is not mounted at all")
            XCTAssertTrue(line.hasPrefix("- \(compose.directory)/"),
                          "state outside the removed directory survives a purge: \(line)")
        }
        for line in volumeLines where !line.contains("/etc/localtime") {
            XCTAssertTrue(line.hasPrefix("- \(compose.directory)/"),
                          "state outside the removed directory survives a purge: \(line)")
        }
        XCTAssertNotEqual(compose.directory, "/opt/gitlab")
    }

    func testGitLabFootprintDominatesTheSizingScreen() {
        let alone = ServiceRegistry.requirements(for: [.gitlab])
        XCTAssertGreaterThanOrEqual(alone.memoryGB, 8)
        let heaviestOther = ServiceRegistry.all
            .filter { $0.id != .gitlab }
            .map(\.resources.memoryMB)
            .max() ?? 0
        XCTAssertGreaterThan(GitLabService().resources.memoryMB, heaviestOther * 2,
                             "GitLab must not be sized as if it were another ordinary service")
    }

    // MARK: - Mailu

    func testMailuProvisionsItsAdminExactlyOnce() throws {
        let env = try XCTUnwrap(MailuService().composeFile(context)?.envTemplate)
        XCTAssertTrue(env.contains("INITIAL_ADMIN_ACCOUNT=admin"))
        XCTAssertTrue(env.contains("INITIAL_ADMIN_MODE=ifmissing"))
        XCTAssertTrue(env.contains("INITIAL_ADMIN_PW=__RANDOM__"),
                      "the admin password must be generated on the server")
        XCTAssertTrue(env.contains("SECRET_KEY=__RANDOM__"))
    }

    func testMailuLeavesACMEToCaddyAndStillGetsACertificate() throws {
        let service = MailuService()
        let env = try XCTUnwrap(service.composeFile(context)?.envTemplate)
        XCTAssertTrue(env.contains("TLS_FLAVOR=mail"))
        XCTAssertFalse(env.contains("TLS_FLAVOR=letsencrypt"))
        XCTAssertFalse(env.contains("TLS_FLAVOR=mail-letsencrypt"))
        let steps = service.setupSteps(context).joined(separator: "\n")
        XCTAssertTrue(steps.contains("\(MailuService.certSyncUnit).timer"))
        XCTAssertTrue(steps.contains("/certs/cert.pem") || steps.contains("$DEST/cert.pem"))
        XCTAssertEqual(service.webIngress(context)?.upstreamHTTPS, false)
    }

    func testMailuTrustsTheBridgeGatewayAsItsProxy() throws {
        let env = try XCTUnwrap(MailuService().composeFile(context)?.envTemplate)
        XCTAssertTrue(env.contains("REAL_IP_FROM=10.254.29.1"), env)
        XCTAssertFalse(env.contains("REAL_IP_FROM=127.0.0.1"))
        let compose = try XCTUnwrap(MailuService().composeFile(context)?.composeContents)
        XCTAssertTrue(compose.contains("subnet: 10.254.29.0/24"))
        XCTAssertTrue(env.contains("SUBNET=10.254.29.0/24"))
    }

    func testMailuAnswersOnEveryMailDomain() throws {
        let multi = ServiceContext(domain: "example.com",
                                   additionalDomains: ["example.org", "example.net"],
                                   sshUser: "admin")
        let env = try XCTUnwrap(MailuService().composeFile(multi)?.envTemplate)
        XCTAssertTrue(env.contains("HOSTNAMES=mail.example.com,mail.example.org,mail.example.net"),
                      env)
    }

    func testMailuBackupKeepsKeysAndSkipsTheQueue() throws {
        let plan = try XCTUnwrap(MailuService().actions(context).backup?.wrapper?.plan.archive)
        XCTAssertEqual(plan.dataPath, "/opt/mailu")
        XCTAssertTrue(plan.encryptsByDefault, "mail, password hashes and DKIM keys")
        XCTAssertTrue(plan.excludes.contains("mailu/mailqueue"))
        XCTAssertTrue(plan.excludes.contains("mailu/filter"))
        XCTAssertFalse(plan.quiesceServices.isEmpty,
                       "a maildir copied while Dovecot writes to it is a torn backup")
    }

    func testMailuUninstallRemovesItsTimerAndScripts() {
        let steps = MailuService().uninstallSpec(context).postSteps
            .joined(separator: "\n")
            .replacingOccurrences(of: "'", with: "")
        XCTAssertTrue(steps.contains("\(MailuService.certSyncUnit).timer"))
        XCTAssertTrue(steps.contains(MailuService.certSyncScriptPath))
        XCTAssertTrue(steps.contains(MailuService.dkimDumpScriptPath))
        XCTAssertTrue(steps.contains("\(MailuService.certSyncScriptPath).bak.*"),
                      "the .bak copies of a managed file are litter too")
    }

    func testMailuSpeaksTheCLIAndPublishesTheAdminItAdvertises() throws {
        let service = MailuService()
        let env = try XCTUnwrap(service.composeFile(context)?.envTemplate)
        XCTAssertTrue(env.contains("ADMIN=true"))

        let steps = service.setupSteps(context).joined(separator: "\n")
        XCTAssertTrue(steps.contains("config-export -j"))
        XCTAssertFalse(steps.contains("--format=json"))
        XCTAssertTrue(steps.contains("config-import -q -u"))
        XCTAssertTrue(steps.contains("'domain:'"))
        XCTAssertFalse(steps.contains("'domains:'"))
        XCTAssertTrue(steps.contains("config-export -d -j domain"))
    }

    /// The firewall may only name ports the engine answers on
    func testMailuOpensOnlyThePortsItActuallyServes() {
        XCTAssertEqual(MailuService().firewallPorts(context).map(\.port).sorted(),
                       [25, 465, 993, 4190])
    }

    func testUpstreamPortsAreUnique() {
        let ports = ServiceRegistry.all.compactMap { $0.webIngress(context)?.upstreamPort }
        XCTAssertEqual(ports.count, Set(ports).count)
    }

    func testEveryServiceCanBeAskedForItsLog() {
        for service in ServiceRegistry.all {
            let actions = service.actions(context)
            guard let logs = actions.logs else {
                XCTFail("\(service.id.rawValue) has no log command")
                continue
            }
            XCTAssertEqual(logs.privileged.binaryPath, "/usr/bin/docker", service.id.rawValue)
            switch actions.statusProbe {
            case .container(let name, _):
                XCTAssertEqual(logs.privileged.arguments,
                               "logs --tail 500 --timestamps \(name)", service.id.rawValue)
            case .composeProject(let project, _):
                XCTAssertEqual(logs.privileged.arguments,
                               "compose -p \(project) logs --tail 500 --timestamps",
                               service.id.rawValue)
            }
        }
    }

    func testEveryLogCommandIsWhitelisted() {
        for service in ServiceRegistry.all {
            guard let logs = service.actions(context).logs else { continue }
            let expected = logs.privileged.sudoersLine(user: context.sshUser)
            XCTAssertTrue(service.sudoersLines(context).contains(expected),
                          "\(service.id.rawValue) may run a log command it is not granted")
        }
    }
}

final class GenerationStringSafetyTests: XCTestCase {
    private func localizationSources() throws -> [URL] {
        // …/Tests/ServiceCatalogTests/<this file> → …/Sources/ServiceCatalog/Localization
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ServiceCatalogTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/ServiceCatalog/Localization")
        let files = try FileManager.default.contentsOfDirectory(at: dir,
                                                                includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "swift" }
    }

    func testNoTranslationCarriesShellMetacharacters() throws {
        let sources = try localizationSources()
        XCTAssertFalse(sources.isEmpty, "no localization sources found next to the tests")
        let pattern = try NSRegularExpression(pattern: #"^\s*\.[a-z]{2}:\s*"(.*)"[,]?\s*$"#)
        var checked = 0
        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let raw = String(line)
                let range = NSRange(raw.startIndex..., in: raw)
                guard let match = pattern.firstMatch(in: raw, range: range),
                      let valueRange = Range(match.range(at: 1), in: raw) else { continue }
                let value = String(raw[valueRange])
                checked += 1
                let where_ = "\(source.lastPathComponent):\(number + 1)"
                XCTAssertFalse(value.contains("`"),
                               "\(where_): a backtick is command substitution inside the "
                               + "double-quoted shell line this string lands in")
                XCTAssertFalse(value.contains("$"),
                               "\(where_): '$' expands in the shell line this string lands in")
                XCTAssertFalse(value.replacingOccurrences(of: "\\\"", with: "").contains("\""),
                               "\(where_): an unescaped quote closes the shell string")
            }
        }
        XCTAssertGreaterThan(checked, 200, "the scan matched suspiciously few translations")
    }
}
final class MinecraftVersionReportTests: XCTestCase {
    private func report(version: String) -> String {
        var settings = ServiceSettings()
        settings.minecraftJavaVersion = version
        let context = ServiceContext(domain: "example.com", sshUser: "admin", settings: settings)
        return MinecraftJavaService().reportSteps(context).joined(separator: "\n")
    }

    func testAnUnpinnedVersionIsNamed() {
        XCTAssertTrue(report(version: "").contains(L10nServices.minecraftVersionFollowsLatest(.en)))
    }

    func testAPinnedVersionIsNotToldItsWorldWillMove() {
        XCTAssertFalse(report(version: "1.21.4").contains(L10nServices.minecraftVersionFollowsLatest(.en)))
    }
}

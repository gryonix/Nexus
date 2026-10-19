import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Deterministic key provider so generation is reproducible in tests
private final class DashboardFixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    private var counter = 0
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        counter += 1
        return WireGuardKeyPair(privateKey: "PRIV\(counter)", publicKey: "PUB\(counter)")
    }
}

final class DashboardAccessTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    private func inputB(dashboardAccess: DashboardAccessInput? = nil,
                        services: Set<ServiceID> = [.mailcow, .vaultwarden],
                        serviceSettings: ServiceSettings = ServiceSettings()) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay,
                           publicAddress: .ipv4("203.0.113.4"),
                           vpnAddress: .ipv4("10.8.0.1"),
                           distribution: .debian),
                ServerNode(role: .homeBackend,
                           publicAddress: nil,
                           vpnAddress: .ipv4("10.8.0.2"),
                           distribution: .debian)
            ],
            dashboardAccess: dashboardAccess,
            services: services,
            serviceSettings: serviceSettings
        )
    }

    private func access() -> DashboardAccessInput {
        DashboardAccessInput(sshUser: "admin", appPublicKey: appKey)
    }

    private func scripts(from input: MailRecipeInput) throws -> (vps: String, home: String) {
        let bundle = try MailRecipe(keyProvider: DashboardFixedKeyProvider()).generate(from: input)
        let vps = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-vps.sh" })
        let home = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-home-server.sh" })
        return (vps.contents, home.contents)
    }

    // MARK: - Opt-in / opt-out

    func testWithoutAccessScriptsUnchanged() throws {
        let (vps, home) = try scripts(from: try inputB())
        for script in [vps, home] {
            XCTAssertFalse(script.contains("gryonixnexus-control"))
            XCTAssertFalse(script.contains("bot-backup.sh"))
            XCTAssertFalse(script.contains("vaultwarden-update.sh"))
            XCTAssertFalse(script.contains("authorized_keys"))
        }
    }

    func testStillExactlyTwoShellScripts() throws {
        let bundle = try MailRecipe(keyProvider: DashboardFixedKeyProvider())
            .generate(from: try inputB(dashboardAccess: access()))
        let shellScripts = bundle.artifacts.filter { $0.kind == .shellScript }
        XCTAssertEqual(shellScripts.map(\.fileName).sorted(),
                       ["setup-home-server.sh", "setup-vps.sh"])
    }

    // MARK: - Section contents

    func testBothScriptsCreateLockedControlUser() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for script in [vps, home] {
            // The bot user is created idempotently, before the key install…
            XCTAssertTrue(script.contains("useradd --create-home --shell /bin/bash 'admin'"))
            let created = try XCTUnwrap(script.range(of: "useradd --create-home"))
            let keyInstalled = try XCTUnwrap(script.range(of: "authorized_keys"))
            XCTAssertLessThan(created.lowerBound, keyInstalled.lowerBound)
            // …logs in by SSH key only (password stays locked)…
            XCTAssertTrue(script.contains("passwd -l 'admin'"))
            // …and gets no extra groups: rights come from sudoers alone.
            XCTAssertFalse(script.contains("usermod"))
            XCTAssertFalse(script.contains("--groups"))
        }
    }

    func testExistingUserModeLeavesTheAccountUntouched() throws {
        let existing = DashboardAccessInput(sshUser: "admin", createUser: false, appPublicKey: appKey)
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: existing))
        for script in [vps, home] {
            XCTAssertTrue(script.contains("id -u 'admin' >/dev/null 2>&1 || fail"),
                          "a missing account must fail fast")
            XCTAssertFalse(script.contains("useradd"))
            XCTAssertFalse(script.contains("passwd -l"), "locking would cut off password login")
            XCTAssertFalse(script.contains("$USER_HOME/.ssh/authorized_keys"),
                           "the app key is not installed for existing users")
            XCTAssertTrue(script.contains("/etc/sudoers.d/gryonixnexus-control"),
                          "the sudoers whitelist is still installed")
        }
    }

    func testBothScriptsInstallAppKeyIdempotently() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for script in [vps, home] {
            XCTAssertTrue(script.contains("APP_KEY='\(appKey)'"))
            XCTAssertTrue(script.contains("grep -qxF \"$APP_KEY\""))
            XCTAssertTrue(script.contains("chmod 600 \"$USER_HOME/.ssh/authorized_keys\""))
        }
    }

    func testRewritingAuthorizedKeysAsRootHandsOwnershipBack() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for script in [vps, home] {
            let lines = script.components(separatedBy: "\n")
            let rewrites = lines.indices.filter {
                let line = lines[$0].trimmingCharacters(in: .whitespaces)
                return line.hasPrefix("mv ") && line.contains(".gryonixnexus\" \"")
            }
            XCTAssertEqual(rewrites.count, 2,
                           "expected both authorized_keys rewrites — has a pattern moved?")
            for index in rewrites {
                let quoted = lines[index].components(separatedBy: "\"")
                let target = try XCTUnwrap(quoted.dropLast().last)
                let window = lines[index...].prefix(25)
                let restoresOwner = window.contains {
                    let line = $0.trimmingCharacters(in: .whitespaces)
                    return line.hasPrefix("chown ") && line.contains(target)
                }
                XCTAssertTrue(restoresOwner, """
                    "\(target)" is rewritten as root (line \(index + 1)) and never \
                    chowned back: sshd reads authorized_keys as the account, so a \
                    root-owned copy disables every key it still holds.
                    """)
            }
        }
    }

    func testSudoersValidatedByVisudoBeforeInstall() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for script in [vps, home] {
            XCTAssertTrue(script.contains("visudo -cf /etc/sudoers.d/gryonixnexus-control.staged"))
            XCTAssertTrue(script.contains("mv /etc/sudoers.d/gryonixnexus-control.staged /etc/sudoers.d/gryonixnexus-control"))
            XCTAssertTrue(script.contains("chmod 440"))
        }
    }

    func testSudoersLinesPerHost() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))

        XCTAssertTrue(vps.contains("admin ALL=(ALL) NOPASSWD: /sbin/sysctl net.ipv4.ip_forward"))
        XCTAssertFalse(vps.contains("/usr/sbin/sysctl"))
        let vpsSudoers = try XCTUnwrap(
            vps.components(separatedBy: "<<'EOF_SUDOERS'\n").dropFirst().first?
                .components(separatedBy: "\nEOF_SUDOERS").first
        )
        XCTAssertFalse(vpsSudoers.contains("docker"), "VPS whitelist must stay minimal")

        XCTAssertTrue(home.contains("admin ALL=(ALL) NOPASSWD: /usr/sbin/sysctl net.ipv4.ip_forward"))
        XCTAssertFalse(home.contains("admin ALL=(ALL) NOPASSWD: /sbin/sysctl net.ipv4.ip_forward"))

        for host in [vps, home] {
            XCTAssertTrue(host.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart wg-quick@wg0"))
            XCTAssertTrue(host.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sshd"))
            // Mirrors CommandCatalog.rebootHost (dashboard's host reboot).
            XCTAssertTrue(host.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot"))
            XCTAssertTrue(host.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/wg show"))
        }
    }

    func testHomeSudoersWhitelistsDashboardCommands() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access()))
        let expected = [
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker compose -p mailcowdockerized restart",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker compose -p mailcowdockerized ps",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker restart vaultwarden",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker stop vaultwarden",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker start vaultwarden",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker ps",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker ps -a",
            "admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-backup-ctl.sh",
            "admin ALL=(ALL) NOPASSWD: /bin/tar",
            "admin ALL=(ALL) NOPASSWD: /bin/chown admin /opt/backups/vaultwarden/vaultwarden-backup.tar.gz"
        ]
        for line in expected {
            XCTAssertTrue(home.contains(line), "missing sudoers line: \(line)")
        }
        for absent in ["NOPASSWD: /opt/vaultwarden-update.sh",
                       "NOPASSWD: /bin/bash /opt/mailcow-dockerized/update.sh --force",
                       "gryonixnexus-update.sh"] {
            XCTAssertFalse(home.contains(absent), "the whitelist still carries: \(absent)")
        }
    }

    func testHomeExemptsTunnelPeerFromSSHDPenalties() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        XCTAssertTrue(home.contains("if sshd -T 2>/dev/null | grep -qi '^persourcepenalties'; then"))
        XCTAssertTrue(home.contains("printf 'PerSourcePenaltyExemptList %s\\n' '10.8.0.1' > /etc/ssh/sshd_config.d/60-gryonixnexus-tunnel.conf"))
        XCTAssertFalse(vps.contains("PerSourcePenaltyExemptList"),
                       "clients hit the VPS from arbitrary IPs — no exemption there")
    }

    func testAdminLockdownSwitchIsWhitelistedWithTheVPNPanel() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                       services: [.mailcow, .shadowsocks]))
        XCTAssertTrue(home.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-admin-lockdown.sh\n"),
                      "home sudoers missing the args-free lockdown entry")
        XCTAssertFalse(home.contains("NOPASSWD: /opt/gryonixnexus-admin-lockdown.sh on"),
                       "per-verb entries replaced by the args-free line")
        XCTAssertFalse(vps.contains("gryonixnexus-admin-lockdown"),
                       "the VPS has no Caddy — no lockdown there")
    }

    func testDockerHostInstallsContainerControlWrapperAndSudoers() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        // The wrapper lands on the docker host…
        XCTAssertTrue(home.contains("chmod 750 '/opt/gryonixnexus-container-ctl.sh'"),
                      "container control wrapper not installed on the services host")
        XCTAssertTrue(home.contains(#"exec docker "$ACTION" "$NAME""#),
                      "wrapper must run docker with the validated action + name")
        // …validates its arguments before touching docker…
        XCTAssertTrue(home.contains("start|stop|restart)"),
                      "wrapper must whitelist the action")
        // …and is whitelisted ONCE (no per-container-name sudoers entries).
        XCTAssertTrue(home.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-container-ctl.sh"),
                      "wrapper not whitelisted in sudoers")
        XCTAssertFalse(vps.contains("gryonixnexus-container-ctl"),
                       "the VPS has no docker services — no container wrapper there")
    }

    func testRestoreWrapperInstalledAndWhitelisted() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                      services: [.mailcow, .vaultwarden]))
        XCTAssertTrue(home.contains("chmod 750 '/opt/gryonixnexus-restore.sh'"),
                      "restore wrapper not installed on the services host")
        XCTAssertTrue(home.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-restore.sh"),
                      "restore wrapper not whitelisted in sudoers")
        XCTAssertTrue(home.contains("echo 'GRYONIXNEXUS_RESTORE_DONE'"),
                      "wrapper must announce success with the pinned marker")
        // Only the two services it knows how to put back.
        XCTAssertTrue(home.contains("mailcow) restore_mailcow ;;"))
        XCTAssertTrue(home.contains("vaultwarden) restore_vaultwarden ;;"))
        XCTAssertFalse(vps.contains("gryonixnexus-restore"),
                       "the VPS runs no restorable services")
    }

    func testRestoreWrapperRefusesPathsOutsideBackupDirs() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                    services: [.mailcow, .vaultwarden]))
        XCTAssertTrue(home.contains(#"*..*) echo "invalid path: ${ARCHIVE}" >&2; exit 2 ;;"#),
                      "wrapper must refuse traversal")
        XCTAssertTrue(home.contains(#""$MAILCOW_BACKUPS"/*|"$VW_BACKUPS"/*) ;;"#),
                      "wrapper must confine archives to the backup directories")
        XCTAssertTrue(home.contains("--passphrase-fd 0"),
                      "GPG passphrase must be read from stdin")
        XCTAssertTrue(home.contains(#"tar -tzf "$plain""#),
                      "archive must be verified before the container is stopped")
        XCTAssertTrue(home.contains(#"previous="${VW_DATA}.pre-restore-$STAMP""#),
                      "previous data must be kept for rollback")
        XCTAssertFalse(home.contains(#"-xzf "$plain" -C /;"#) || home.contains(#"-xzf "$plain" -C / "#),
                       "an archive is never unpacked over the root")
        XCTAssertTrue(home.contains(#"mv "$stage/$root" "$VW_DATA""#),
                      "only the archived data directory is moved into place")
    }

    func testRestoreStagingDirectoriesAreCreated() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                    services: [.mailcow, .vaultwarden]))
        XCTAssertTrue(home.contains("install -d '/opt/backups/mailcow/incoming'"))
        XCTAssertTrue(home.contains("install -d -o 'admin' -m 0750 '/opt/backups/vaultwarden/incoming'"))
    }

    func testMailcowWrapperExportsLocationAndRotates() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access()))
        XCTAssertTrue(home.contains("export MAILCOW_BACKUP_LOCATION='/opt/backups/mailcow'"))
        XCTAssertTrue(home.contains(#"chmod 0777 "$MAILCOW_BACKUP_LOCATION""#))
        XCTAssertTrue(home.contains("backup_and_restore.sh' backup all"))
        XCTAssertTrue(home.contains(#"tar -czf "$MAILCOW_BACKUP_LOCATION/$base.tar.gz""#))
        XCTAssertTrue(home.contains("tail -n +8 | xargs -r rm -rf"))
        XCTAssertTrue(home.contains("mailcow-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f"))
        XCTAssertTrue(home.contains("chmod 750 '/opt/mailcow-dockerized/bot-backup.sh'"))
    }

    func testUninstallRemovesTheBackupCopiesItLeftBehind() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                      services: [.mailcow, .vaultwarden]))
        XCTAssertTrue(home.contains("/opt/gryonixnexus-*.bak.*"))
        XCTAssertTrue(home.contains("/etc/caddy/Caddyfile.bak.*"))
        XCTAssertTrue(home.contains("/etc/wireguard/wg0.conf.bak.*"))
        XCTAssertTrue(vps.contains("/etc/wireguard/wg0.conf.bak.*"))
        XCTAssertTrue(vps.contains("/opt/gryonixnexus-*.bak.*"))
        XCTAssertFalse(vps.contains("Caddyfile.bak"))
    }

    // MARK: - Control-plane agent

    func testUninstallRemovesTheControlPlaneAgent() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for (role, script) in [("vps", vps), ("home", home)] {
            let wrapper = try uninstallWrapper(in: script)
            XCTAssertTrue(wrapper.contains("if [ -f /etc/systemd/system/gryonixnexusd.service ]; then"),
                          "\(role): the removal must be guarded on existence")
            XCTAssertTrue(wrapper.contains("systemctl disable --now 'gryonixnexusd.service' >/dev/null 2>&1 || true"),
                          "\(role): the unit must be stopped and disabled")
            XCTAssertTrue(wrapper.contains("rm -f '/etc/systemd/system/gryonixnexusd.service'"),
                          "\(role): the unit file must go")
            XCTAssertTrue(wrapper.contains("systemctl daemon-reload || true"), role)
            XCTAssertTrue(wrapper.contains("rm -f '/usr/local/bin/gryonixnexusd' '/run/gryonixnexusd.sock'"),
                          "\(role): binary and socket must go")
            XCTAssertTrue(wrapper.contains("rm -rf '/var/lib/gryonixnexus/agent'"),
                          "\(role): the agent's own state must go")
        }
    }

    func testUninstallRemovesThePredecessorAgent() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for (role, script) in [("vps", vps), ("home", home)] {
            let wrapper = try uninstallWrapper(in: script)
            XCTAssertTrue(wrapper.contains("if [ -f /etc/systemd/system/gryonixnexus.service ]; then"), role)
            XCTAssertTrue(wrapper.contains("systemctl disable --now 'gryonixnexus.service' >/dev/null 2>&1 || true"),
                          role)
            XCTAssertTrue(wrapper.contains("rm -f '/etc/systemd/system/gryonixnexus.service'"), role)
            XCTAssertTrue(wrapper.contains("rm -f '/usr/local/bin/gryonixd' '/run/gryonixd.sock'"), role)
        }
    }

    func testAgentCleanupNeverNamesTheSharedProductDirectory() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for (role, script) in [("vps", vps), ("home", home)] {
            let block = try agentCleanupBlock(in: script)
            let shared = removalTargets(in: block).filter { $0.hasPrefix("/var/lib/gryonixnexus") }
            XCTAssertEqual(shared, ["/var/lib/gryonixnexus/agent"],
                           "\(role): the agent cleanup may only remove its own subdirectory")
        }
    }

    func testAgentIsRemovedOnlyByTheFullErase() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access()))
        let wrapper = try uninstallWrapper(in: home)
        let allStart = try XCTUnwrap(wrapper.range(of: "uninstall_all() {"))
        let firstMention = try XCTUnwrap(wrapper.range(of: "gryonixnexusd"))
        XCTAssertGreaterThan(firstMention.lowerBound, allStart.lowerBound,
                             "the agent must not be touched by a per-service target")
    }

    func testAgentIsStoppedBeforeTheSharedStateDirectoryIsRemoved() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for (role, script) in [("vps", vps), ("home", home)] {
            let wrapper = try uninstallWrapper(in: script)
            let stopped = try XCTUnwrap(wrapper.range(of: "systemctl disable --now 'gryonixnexusd.service'"))
            let wiped = try XCTUnwrap(wrapper.range(of: "rm -rf /var/lib/gryonixnexus\n"))
            XCTAssertLessThan(stopped.lowerBound, wiped.lowerBound,
                              "\(role): the agent would re-create the directory after the rm")
        }
    }

    private func uninstallWrapper(in script: String) throws -> String {
        let start = try XCTUnwrap(script.range(of: "cat > /opt/gryonixnexus-uninstall.sh <<'EOF_UNINSTALL'\n"))
        let end = try XCTUnwrap(script.range(of: "\nEOF_UNINSTALL", range: start.upperBound..<script.endIndex))
        return String(script[start.upperBound..<end.lowerBound])
    }

    private func agentCleanupBlock(in script: String) throws -> String {
        let wrapper = try uninstallWrapper(in: script)
        let start = try XCTUnwrap(wrapper.range(of: "# Control-plane agent:"))
        let end = try XCTUnwrap(wrapper.range(of: "systemctl disable --now gryonixnexus-metrics",
                                              range: start.upperBound..<wrapper.endIndex))
        return String(wrapper[start.upperBound..<end.lowerBound])
    }

    func testEveryRemovedManagedFileHasItsBackupCopiesRemovedToo() throws {
        var settings = ServiceSettings()
        settings.wireguardVPNPort = 51821
        let (vps, home) = try scripts(from: try inputB(
            dashboardAccess: access(),
            services: [.mailcow, .vaultwarden, .nextcloud, .immich, .wireguardVPN],
            serviceSettings: settings))
        for (role, script) in [("vps", vps), ("home", home)] {
            let removed = Set(removalTargets(in: script))
            for path in backedUpPaths(in: script) where removed.contains(path) {
                let copy = "\(path).bak.1785875843"
                XCTAssertTrue(removed.contains { fnmatch($0, copy, 0) == 0 },
                              "\(role): uninstall removes \(path) but keeps \(path).bak.*")
            }
        }
    }

    /// Paths passed to the `backup` helper, i.e
    private func backedUpPaths(in script: String) -> [String] {
        script.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("backup /") else { return nil }
            return String(trimmed.dropFirst("backup ".count))
        }
    }

    /// Every argument of an `rm -f` / `rm -rf`, unquoted
    private func removalTargets(in script: String) -> [String] {
        script.split(separator: "\n").flatMap { line -> [String] in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("rm -f ") || trimmed.hasPrefix("rm -rf ") else { return [] }
            return trimmed.split(separator: " ").dropFirst(2)
                .map { $0.replacingOccurrences(of: "'", with: "") }
                .filter { $0.hasPrefix("/") }
        }
    }

    func testMailcowRestoreAsksForAllDatasets() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                    services: [.mailcow, .vaultwarden]))
        XCTAssertTrue(home.contains(#"printf '1\n0\nn\n'"#))
        XCTAssertFalse(home.contains(#"printf '1\n1\n2\n3\n4\n5\n\n'"#))
        XCTAssertTrue(home.contains(#"timeout 3600 "$MAILCOW_PATH/helper-scripts/backup_and_restore.sh" restore"#))
    }

    func testBackupRootIsNotTraversableByOtherAccounts() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access()))
        XCTAssertTrue(home.contains("install -d '/opt/backups'"))
        XCTAssertTrue(home.contains("chmod 0750 '/opt/backups'"))
        let root = try XCTUnwrap(home.range(of: "chmod 0750 '/opt/backups'"))
        let child = try XCTUnwrap(home.range(of: "install -d '/opt/backups/mailcow'"))
        XCTAssertTrue(root.upperBound < child.lowerBound)
    }

    func testScheduleUsageMatchesWhatTheWrapperParses() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access()))
        let usage = try XCTUnwrap(
            home.split(separator: "\n").first { $0.contains("set-schedule") && $0.hasPrefix("#") },
            "the wrapper must document set-schedule")
        // Every literal the parser cases on appears in the header…
        for accepted in ["off", "every:"] {
            XCTAssertTrue(usage.contains(accepted),
                          "usage omits the accepted form \(accepted)")
            XCTAssertTrue(home.contains("\(accepted)) ") || home.contains("\(accepted)*)"),
                          "parser lost the \(accepted) arm")
        }
        // …and nothing it would reject does.
        for rejected in ["daily", "weekly", "monthly"] {
            XCTAssertFalse(usage.contains(rejected),
                           "usage advertises \(rejected), which do_set_schedule rejects")
        }
    }

    /// GitLab's archive is the whole service tree MINUS the logs
    func testGitLabArchivesItsSecretsAndSkipsItsLogs() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                     services: [.gitlab]))
        let body = try XCTUnwrap(home.range(of: "backup_gitlab() {").map {
            String(home[$0.lowerBound...].prefix(while: { $0 != "\u{7D}" }))
        })
        XCTAssertTrue(body.contains("--exclude 'gitlab-ce/logs'"),
                      "the log tree must stay out of the archive")
        XCTAssertTrue(body.contains("-C '/opt' 'gitlab-ce'"),
                      "the whole tree — including config/ — has to be archived")
        // The estimate measures what is actually archived.
        XCTAssertTrue(home.contains("gitlab) dir='/opt/backups/gitlab'; paths=('/opt/gitlab-ce/config' '/opt/gitlab-ce/data')"),
                      "the estimate must count config and data, and not the logs")
        XCTAssertTrue(body.contains("gd_compose_stop 'gitlab' 'gitlab'"),
                      "the container must be stopped for a consistent cold backup")
        XCTAssertTrue(body.contains("gd_compose_start 'gitlab' 'gitlab'"),
                      "and started again on every path")
    }

    func testBackupRootLockSkipsTopLevelDirectories() {
        XCTAssertEqual(DashboardAccessSections.enclosingBackupRoot(of: "/opt/backups/mailcow"),
                       "/opt/backups")
        XCTAssertEqual(DashboardAccessSections.enclosingBackupRoot(of: "/srv/gd/backups/mailcow/"),
                       "/srv/gd/backups")
        XCTAssertNil(DashboardAccessSections.enclosingBackupRoot(of: "/opt/mailcow"))
        XCTAssertNil(DashboardAccessSections.enclosingBackupRoot(of: "/mailcow"))
        XCTAssertNil(DashboardAccessSections.enclosingBackupRoot(of: "mailcow"))
    }

    func testTheVaultwardenUpdateScriptIsNoLongerWrittenButIsStillCleanedUp() throws {
        let (_, home) = try scripts(from: try inputB(dashboardAccess: access()))
        XCTAssertFalse(home.contains("cat > /opt/vaultwarden-update.sh"))
        XCTAssertFalse(home.contains("chmod 750 /opt/vaultwarden-update.sh"))
        XCTAssertFalse(home.contains("NOPASSWD: /opt/vaultwarden-update.sh"))
        XCTAssertTrue(home.contains("rm -f /opt/vaultwarden-update.sh"),
                      "the uninstall wrapper still removes what earlier installs left")
    }

    func testVPSHasNoHomeOnlyProvisioning() throws {
        let (vps, _) = try scripts(from: try inputB(dashboardAccess: access()))
        XCTAssertFalse(vps.contains("bot-backup.sh"))
        XCTAssertFalse(vps.contains("vaultwarden-update.sh"))
        XCTAssertFalse(vps.contains("MAILCOW_BACKUP_LOCATION"))
    }

    #if os(macOS)
    func testGeneratedScriptsPassBashSyntaxCheck() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for (name, contents) in [("vps", vps), ("home", home)] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gryonixnexus-\(name)-\(UUID().uuidString).sh")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", url.path]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                     encoding: .utf8) ?? ""
            XCTAssertEqual(process.terminationStatus, 0,
                           "bash -n failed for \(name) script:\n\(errorOutput)")
        }
    }
    #endif

    // MARK: - Validation

    func testRejectsInvalidUser() throws {
        let bad = DashboardAccessInput(sshUser: "Root User", appPublicKey: appKey)
        XCTAssertThrowsError(try MailRecipe().generate(from: try inputB(dashboardAccess: bad))) { error in
            guard case ValidationError.inconsistentTopology = error else {
                return XCTFail("expected inconsistentTopology, got \(error)")
            }
        }
    }

    func testRejectsNonEd25519Key() throws {
        let bad = DashboardAccessInput(sshUser: "admin", appPublicKey: "ssh-rsa AAAA...")
        XCTAssertThrowsError(try MailRecipe().generate(from: try inputB(dashboardAccess: bad)))
    }

    func testSingleHostGetsDashboardAccessWithoutTunnelCommands() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost,
                                 publicAddress: .ipv4("203.0.113.4"),
                                 vpnAddress: nil,
                                 distribution: .debian)],
            dashboardAccess: access(),
            services: [.mailcow, .vaultwarden]
        )
        let bundle = try MailRecipe(keyProvider: DashboardFixedKeyProvider()).generate(from: input)
        let script = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }).contents

        XCTAssertTrue(script.contains("APP_KEY='\(appKey)'"))
        XCTAssertTrue(script.contains("visudo -cf /etc/sudoers.d/gryonixnexus-control.staged"))
        XCTAssertTrue(script.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sshd"))
        XCTAssertTrue(script.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot"))
        XCTAssertTrue(script.contains("admin ALL=(ALL) NOPASSWD: /usr/bin/docker compose -p mailcowdockerized ps"))
        XCTAssertTrue(script.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-backup-ctl.sh"))
        // No tunnel — no tunnel-related lines in sudoers.
        XCTAssertFalse(script.contains("NOPASSWD: /usr/bin/systemctl restart wg-quick"))
        XCTAssertFalse(script.contains("NOPASSWD: /usr/bin/wg show"))
        XCTAssertFalse(script.contains("sysctl net.ipv4.ip_forward"))
    }

    // MARK: - Uninstall wrapper

    func testUninstallWrapperInstalledAndWhitelisted() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access()))
        for script in [vps, home] {
            XCTAssertTrue(script.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-uninstall.sh"))
            XCTAssertTrue(script.contains("GRYONIXNEXUS_UNINSTALL_DONE"))
        }
        // Services host: one arm per installed service, purge stays opt-in.
        XCTAssertTrue(home.contains("uninstall_mailcow()"))
        XCTAssertTrue(home.contains("uninstall_vaultwarden()"))
        XCTAssertTrue(home.contains("  mailcow) uninstall_mailcow ;;"))
        // Two independent purge flags, parsed order-agnostically.
        XCTAssertTrue(home.contains("if [ \"$PURGE_DATA\" -eq 1 ]; then"))
        XCTAssertTrue(home.contains("--purge-data) PURGE_DATA=1 ;;"))
        XCTAssertTrue(home.contains("--purge-backups) PURGE_BACKUPS=1 ;;"))
        // Data directories are only ever removed inside the purge guard.
        XCTAssertTrue(home.contains("purge_path '/opt/mailcow-dockerized'"))
        XCTAssertTrue(home.contains("rm -rf '/opt/backups/vaultwarden'"))
        // Full cleanup drops the whitelist itself, last.
        XCTAssertTrue(home.contains("rm -f /etc/sudoers.d/gryonixnexus-control"))
        // The relay wrapper only knows --all.
        XCTAssertTrue(vps.contains("if [ \"$TARGET\" != \"--all\" ]; then"))
        XCTAssertTrue(vps.contains("wg-quick@wg0"))
    }

    func testUninstallWrapperVPNGroupAndCaddySites() throws {
        let input = try inputB(dashboardAccess: access(), services: [.xrayReality])
        let home = try scripts(from: input).home
        XCTAssertTrue(home.contains("uninstall_vpn()"))
        XCTAssertTrue(home.contains("  vpn) uninstall_vpn ;;"))
        XCTAssertTrue(home.contains("compose_down 'vpnpanel'"))
        XCTAssertTrue(home.contains("compose_down 'xray'"))
        XCTAssertTrue(home.contains("remove_caddy_site 'vpn.example.com'"))
        XCTAssertTrue(home.contains("ip link delete wgpanel"))
    }

    func testUninstallOfOneServiceDropsItsOwnSudoersLines() throws {
        let home = try scripts(from: try inputB(dashboardAccess: access(), services: [.jellyfin])).home
        let jellyfinFunction = try functionBody(home, name: "uninstall_jellyfin")
        XCTAssertTrue(jellyfinFunction.contains("remove_sudoers_lines"))
        for line in [
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker ps -a",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker restart jellyfin",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker start jellyfin",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker stop jellyfin",
            "admin ALL=(ALL) NOPASSWD: /usr/bin/docker logs --tail 500 --timestamps jellyfin"
        ] {
            XCTAssertTrue(jellyfinFunction.contains("'\(line)'"), "missing removal of: \(line)")
        }
        // The helper itself: staged, validated, never a bare `rm`/edit.
        XCTAssertTrue(home.contains("remove_sudoers_lines() {"))
        XCTAssertTrue(home.contains("visudo -cf \"$tmp\""))
    }

    func testUninstallDoesNotDropASudoersLineAnotherInstalledServiceStillNeeds() throws {
        let home = try scripts(
            from: try inputB(dashboardAccess: access(), services: [.jellyfin, .adguardHome])
        ).home
        let sharedProbe = "admin ALL=(ALL) NOPASSWD: /usr/bin/docker ps -a"
        XCTAssertEqual(home.components(separatedBy: sharedProbe).count - 1, 1)

        let jellyfinFunction = try functionBody(home, name: "uninstall_jellyfin")
        XCTAssertFalse(jellyfinFunction.contains("'\(sharedProbe)'"),
                       "jellyfin's removal must not drop the probe adguard-home still needs")
        XCTAssertTrue(jellyfinFunction.contains("'admin ALL=(ALL) NOPASSWD: /usr/bin/docker restart jellyfin'"))

        let adguardFunction = try functionBody(home, name: "uninstall_adguard_home")
        XCTAssertFalse(adguardFunction.contains("'\(sharedProbe)'"),
                       "adguard-home's removal must not drop the probe jellyfin still needs")
        XCTAssertTrue(adguardFunction.contains(
            "'admin ALL=(ALL) NOPASSWD: /usr/bin/docker restart \(AdGuardHomeService.container)'"))
    }

    private func functionBody(_ script: String, name: String) throws -> String {
        let start = try XCTUnwrap(script.range(of: "\(name)() {\n"))
        let rest = script[start.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "\n}\n"))
        return String(rest[..<end.upperBound])
    }

    func testBothHostsWhitelistTheAgentBridge() throws {
        let (vps, home) = try scripts(from: try inputB(dashboardAccess: access(),
                                                       services: [.mailcow]))
        let grant = "admin ALL=(ALL) NOPASSWD: /usr/local/bin/gryonixnexusd bridge"
        XCTAssertTrue(home.contains(grant), "the services host cannot reach its own agent without this")
        XCTAssertTrue(vps.contains(grant), "the relay is reachable only through its agent")
        XCTAssertEqual(AgentBootstrapSections.bridgeSudoersTarget, "/usr/local/bin/gryonixnexusd bridge")
        XCTAssertEqual(AgentBootstrapSections.bridgeCommand,
                       "sudo -n /usr/local/bin/gryonixnexusd bridge")
        XCTAssertTrue(home.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-agent-bootstrap.sh"))
        XCTAssertTrue(vps.contains("admin ALL=(ALL) NOPASSWD: /opt/gryonixnexus-agent-bootstrap.sh"),
                      "the app updates the relay's agent too")
    }

    func testMailcowReportEmitsDKIMMarker() throws {
        let home = try scripts(from: try inputB(dashboardAccess: access(),
                                                services: [.mailcow])).home
        XCTAssertTrue(home.contains("GRYONIXNEXUS_DKIM dkim._domainkey.example.com $MC_DKIM_TXT"),
                      "the report must carry a parsable DKIM line, not just localized prose")
    }
}

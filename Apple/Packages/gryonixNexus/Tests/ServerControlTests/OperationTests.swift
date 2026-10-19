import XCTest
import ServiceCatalog
@testable import ServerControl

private func makeConfig() -> DashboardConfig {
    var config = DashboardConfig.default
    config.vpsHost = "203.0.113.4"
    config.sshUser = "admin"
    return config
}

final class CommandCatalogTests: XCTestCase {
    func testAValueWithASpaceOrAQuoteCannotRunExtraShell() {
        XCTAssertEqual(CommandCatalog.Vaultwarden.restart(container: "vault warden; reboot"),
                       "sudo docker restart 'vault warden; reboot'")
        XCTAssertEqual(CommandCatalog.Mailcow.update(mailcowPath: "/opt/my mail"),
                       "cd '/opt/my mail' && sudo /bin/bash '/opt/my mail/update.sh' --force")
        XCTAssertEqual(CommandCatalog.Backups.listVaultwarden(backupDir: "/b/it's"),
                       "ls -lht '/b/it'\\''s'/*.gpg")
    }

    func testSudoersSensitiveLiterals() {
        XCTAssertEqual(CommandCatalog.ipForwardingCheck, "sudo sysctl net.ipv4.ip_forward")
        XCTAssertEqual(CommandCatalog.restartWireGuard(interface: "wg0"),
                       "sudo systemctl restart wg-quick@wg0")
        XCTAssertEqual(CommandCatalog.restartSSHD, "sudo systemctl restart sshd")
        XCTAssertEqual(CommandCatalog.rebootHost, "sudo systemctl reboot")
        XCTAssertEqual(CommandCatalog.wgShow, "sudo wg show")
        XCTAssertEqual(CommandCatalog.Mailcow.status,
                       "sudo docker compose -p mailcowdockerized ps")
        XCTAssertEqual(CommandCatalog.Mailcow.restart,
                       "sudo docker compose -p mailcowdockerized restart")
        XCTAssertEqual(CommandCatalog.Mailcow.update(mailcowPath: "/opt/mailcow-dockerized"),
                       "cd /opt/mailcow-dockerized && sudo /bin/bash /opt/mailcow-dockerized/update.sh --force")
        XCTAssertEqual(CommandCatalog.Vaultwarden.status, "sudo docker ps -a")
        XCTAssertEqual(CommandCatalog.Vaultwarden.restart(container: "vaultwarden"),
                       "sudo docker restart vaultwarden")
        XCTAssertEqual(CommandCatalog.Vaultwarden.stop(container: "vaultwarden"),
                       "sudo docker stop vaultwarden")
        XCTAssertEqual(CommandCatalog.Vaultwarden.start(container: "vaultwarden"),
                       "sudo docker start vaultwarden")
        XCTAssertEqual(CommandCatalog.Vaultwarden.update, "sudo /opt/vaultwarden-update.sh")
        XCTAssertEqual(
            CommandCatalog.Mailcow.backup(mailcowPath: "/opt/mailcow-dockerized",
                                          backupDir: "/opt/backups/mailcow"),
            "mkdir -p '/opt/backups/mailcow' && sudo /opt/mailcow-dockerized/bot-backup.sh"
        )
        XCTAssertEqual(CommandCatalog.AdminLockdown.on, "sudo /opt/gryonixnexus-admin-lockdown.sh on")
        XCTAssertEqual(CommandCatalog.AdminLockdown.off, "sudo /opt/gryonixnexus-admin-lockdown.sh off")
        XCTAssertEqual(CommandCatalog.AdminLockdown.status, "sudo /opt/gryonixnexus-admin-lockdown.sh status")
        XCTAssertEqual(CommandCatalog.AdminLockdown.only(hosts: ["vault.x.com", "cloud.x.com"]),
                       "sudo /opt/gryonixnexus-admin-lockdown.sh only vault.x.com cloud.x.com")
    }

    func testAdminLockdownAnswerParsing() {
        XCTAssertEqual(StatusOperations.parseLockdownAnswer("on\n"), .all)
        XCTAssertEqual(StatusOperations.parseLockdownAnswer("off"), .off)
        XCTAssertEqual(StatusOperations.parseLockdownAnswer(""), .off)
        XCTAssertEqual(StatusOperations.parseLockdownAnswer("only vault.x.com cloud.x.com\n"),
                       .only(["vault.x.com", "cloud.x.com"]))
        XCTAssertEqual(StatusOperations.parseLockdownAnswer("only $(evil)"), .off)
        XCTAssertFalse(AdminLockdownState.off.guards("vault.x.com"))
        XCTAssertTrue(AdminLockdownState.all.guards("vault.x.com"))
        XCTAssertTrue(AdminLockdownState.only(["vault.x.com"]).guards("vault.x.com"))
        XCTAssertFalse(AdminLockdownState.only(["vault.x.com"]).guards("cloud.x.com"))
    }

    func testContainerControlLiterals() {
        XCTAssertEqual(CommandCatalog.Containers.controlScriptPath,
                       "/opt/gryonixnexus-container-ctl.sh")
        XCTAssertEqual(CommandCatalog.Containers.control(.restart, container: "nextcloud-app-1"),
                       "sudo /opt/gryonixnexus-container-ctl.sh restart 'nextcloud-app-1'")
        XCTAssertEqual(CommandCatalog.Containers.control(.start, container: "vaultwarden"),
                       "sudo /opt/gryonixnexus-container-ctl.sh start 'vaultwarden'")
        XCTAssertEqual(CommandCatalog.Containers.control(.stop, container: "vaultwarden"),
                       "sudo /opt/gryonixnexus-container-ctl.sh stop 'vaultwarden'")
    }

    func testEncryptedVolumeBackupPinsTarArguments() {
        let dataPath = "/opt/vaultwarden/data"
        let staging = BackupSpec.stagingArchivePath(backupDir: "/opt/backups/vaultwarden",
                                                    container: "vaultwarden")
        let arguments = BackupSpec.archiveArguments(dataPath: dataPath, archivePath: staging)
        XCTAssertEqual(arguments,
                       "czf /opt/backups/vaultwarden/vaultwarden-backup.tar.gz -C / opt/vaultwarden/data")

        let sent = CommandCatalog.Vaultwarden.archive(dataPath: dataPath, archivePath: staging)
        XCTAssertEqual(sent.replacingOccurrences(of: "'", with: ""), "sudo tar \(arguments)")

        let spec = BackupSpec.encryptedVolume(
            container: "vaultwarden", dataPath: dataPath, backupDir: "/opt/backups/vaultwarden",
            stopStart: EncryptedVolumeCommands(
                stop: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "stop vaultwarden"),
                start: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "start vaultwarden")))
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        let tar = spec.privilegedCommands(context).first { $0.binaryPath == "/bin/tar" }
        XCTAssertEqual(tar?.arguments, arguments)
        XCTAssertEqual(tar?.sudoersLine(user: "admin"),
                       "admin ALL=(ALL) NOPASSWD: /bin/tar \(arguments)")
    }

    func testRestoreLiterals() {
        XCTAssertEqual(CommandCatalog.Restore.scriptPath, "/opt/gryonixnexus-restore.sh")
        XCTAssertEqual(CommandCatalog.Restore.doneMarker, "GRYONIXNEXUS_RESTORE_DONE")
        XCTAssertEqual(CommandCatalog.Restore.run(target: "mailcow",
                                                  archivePath: "/opt/backups/mailcow/mailcow-2026.tar.gz"),
                       "sudo /opt/gryonixnexus-restore.sh mailcow '/opt/backups/mailcow/mailcow-2026.tar.gz'")
        XCTAssertEqual(CommandCatalog.Restore.run(target: "vaultwarden",
                                                  archivePath: "/opt/backups/vaultwarden/vw.tar.gz.gpg"),
                       "sudo /opt/gryonixnexus-restore.sh vaultwarden '/opt/backups/vaultwarden/vw.tar.gz.gpg'")
        XCTAssertEqual(CommandCatalog.Restore.stagingDirectory(backupDir: "/opt/backups/mailcow"),
                       "/opt/backups/mailcow/incoming")
    }

    func testUninstallLiterals() {
        XCTAssertEqual(CommandCatalog.Uninstall.scriptPath, "/opt/gryonixnexus-uninstall.sh")
        XCTAssertEqual(CommandCatalog.Uninstall.doneMarker, "GRYONIXNEXUS_UNINSTALL_DONE")
        XCTAssertEqual(CommandCatalog.Uninstall.vpnTarget, "vpn")
        XCTAssertEqual(CommandCatalog.Uninstall.run(target: "mailcow", purge: .none),
                       "sudo /opt/gryonixnexus-uninstall.sh mailcow")
        XCTAssertEqual(CommandCatalog.Uninstall.run(target: "vpn", purge: PurgeOptions(data: true)),
                       "sudo /opt/gryonixnexus-uninstall.sh vpn --purge-data")
        XCTAssertEqual(CommandCatalog.Uninstall.fullCleanup(purge: .none),
                       "sudo /opt/gryonixnexus-uninstall.sh --all")
        XCTAssertEqual(CommandCatalog.Uninstall.fullCleanup(purge: PurgeOptions(data: true)),
                       "sudo /opt/gryonixnexus-uninstall.sh --all --purge-data")
        XCTAssertEqual(CommandCatalog.Uninstall.fullCleanup(purge: PurgeOptions(data: true, backups: true)),
                       "sudo /opt/gryonixnexus-uninstall.sh --all --purge-data --purge-backups")
    }

    func testMailcowDKIMDumpLiterals() {
        XCTAssertEqual(CommandCatalog.Mailcow.dkimScriptPath, "/opt/gryonixnexus-dkim.sh")
        XCTAssertEqual(CommandCatalog.Mailcow.dkimDoneMarker, "GRYONIXNEXUS_DKIM_DONE")
        XCTAssertEqual(CommandCatalog.Mailcow.dkimDump, "sudo /opt/gryonixnexus-dkim.sh")
    }

    func testInstallReportCommand() {
        XCTAssertEqual(CommandCatalog.installReport,
                       "cat /var/lib/gryonixnexus/install-report.txt 2>/dev/null; true")
        XCTAssertFalse(CommandCatalog.installReport.contains("sudo"))
    }

    /// The client-side mirror of the wrapper's path check
    func testRestorePathValidation() {
        let dir = "/opt/backups/vaultwarden"
        XCTAssertTrue(CommandCatalog.Restore.isValidArchivePath("\(dir)/vw.tar.gz.gpg", backupDir: dir))
        XCTAssertTrue(CommandCatalog.Restore.isValidArchivePath("\(dir)/incoming/vw.gpg", backupDir: dir))
        XCTAssertFalse(CommandCatalog.Restore.isValidArchivePath("/etc/shadow", backupDir: dir))
        XCTAssertFalse(CommandCatalog.Restore.isValidArchivePath("\(dir)/../../etc/shadow", backupDir: dir))
        XCTAssertFalse(CommandCatalog.Restore.isValidArchivePath("\(dir)-evil/x.gpg", backupDir: dir))
    }

    func testUploadNameSanitizing() {
        XCTAssertEqual(ServiceOperations.sanitizedUploadName("vw-backup.tar.gz"), "vw-backup.tar.gz")
        XCTAssertEqual(ServiceOperations.sanitizedUploadName("../../etc/shadow"), "shadow")
        XCTAssertEqual(ServiceOperations.sanitizedUploadName("a/b/c.gpg"), "c.gpg")
        XCTAssertEqual(ServiceOperations.sanitizedUploadName("../.."), ".")
        XCTAssertEqual(ServiceOperations.sanitizedUploadName("!!!"), "upload.tar.gz")
        XCTAssertEqual(ServiceOperations.sanitizedUploadName("bad name;rm -rf.gz"), "badnamerm-rf.gz")
    }

    func testProbeCommands() {
        XCTAssertEqual(CommandCatalog.pingSelf(vpsHost: "203.0.113.4"),
                       "ping -c 1 -W 2 '203.0.113.4'")
        XCTAssertEqual(CommandCatalog.pingTunnel(homeWGAddress: "10.8.0.2"),
                       "ping -c 1 -W 2 '10.8.0.2'")
        XCTAssertEqual(CommandCatalog.disk,
                       "df -B1 --output=target,size,used,pcent -x tmpfs -x devtmpfs -x overlay")
        XCTAssertEqual(CommandCatalog.memory, "free -b")
    }

    func testArchiveStripsLeadingSlash() {
        XCTAssertEqual(
            CommandCatalog.Vaultwarden.archive(dataPath: "/opt/vaultwarden/data",
                                               archivePath: "/opt/backups/vw/a.tar.gz"),
            "sudo tar czf '/opt/backups/vw/a.tar.gz' -C / 'opt/vaultwarden/data'"
        )
    }

    func testChownMatchesSudoersLiteral() {
        let staging = CommandCatalog.Vaultwarden.stagingArchivePath(
            backupDir: "/opt/backups/vaultwarden", container: "vaultwarden"
        )
        XCTAssertEqual(staging, "/opt/backups/vaultwarden/vaultwarden-backup.tar.gz")
        XCTAssertEqual(
            CommandCatalog.Vaultwarden.chownArchive(user: "admin", archivePath: staging),
            "sudo chown 'admin' '/opt/backups/vaultwarden/vaultwarden-backup.tar.gz'"
        )
    }

    func testRotationKeepsRetention() {
        XCTAssertEqual(
            CommandCatalog.Vaultwarden.rotate(backupDir: "/opt/backups/vw", retention: 7),
            "ls -1t '/opt/backups/vw' 2>/dev/null | grep '\\.gpg$' | tail -n +8"
                + " | while IFS= read -r f; do rm -f -- '/opt/backups/vw'/\"$f\"; done"
        )
    }

    func testRotationNeverDeletesTheNewestBackup() {
        for retention in [0, -3] {
            XCTAssertTrue(CommandCatalog.Vaultwarden.rotate(backupDir: "/b", retention: retention)
                .contains("tail -n +2 "))
        }
    }
}

final class StatusOperationsTests: XCTestCase {
    func testIPForwardingParsesAndRoutesToHost() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("sysctl", stdout: "net.ipv4.ip_forward = 1\n")
        let ops = StatusOperations(runner: runner, config: makeConfig())

        let enabled = try await ops.ipForwarding(on: .home)

        XCTAssertTrue(enabled)
        XCTAssertEqual(runner.calls, [.init(kind: .run,
                                            command: "sudo sysctl net.ipv4.ip_forward",
                                            host: .home)])
    }

    func testGeneralProbeFetchesEveryVPSRowInOneRoundTrip() async throws {
        let runner = FakeSSHCommandRunner()
        let sep = CommandCatalog.generalProbeSeparator
        runner.stub("sysctl", stdout: """
        net.ipv4.ip_forward = 1
        \(sep)
        1 packets transmitted, 1 received, 0% packet loss
        rtt min/avg/max/mdev = 0.3/0.4/0.5/0.1 ms
        \(sep)
        1 packets transmitted, 0 received, 100% packet loss
        """)
        let ops = StatusOperations(runner: runner, config: makeConfig())

        let status = try await ops.generalVPSStatus()

        XCTAssertEqual(runner.calls.count, 1, "one command, not three")
        XCTAssertEqual(runner.calls.first?.host, .vps)
        XCTAssertTrue(status.forwarding)
        XCTAssertTrue(status.selfPing.isAlive, "the first ping section succeeded")
        XCTAssertFalse(status.tunnelPing.isAlive, "the second section lost every packet")
    }

    func testGeneralProbeRejectsATruncatedAnswer() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("sysctl", stdout: "net.ipv4.ip_forward = 1")
        let ops = StatusOperations(runner: runner, config: makeConfig())

        do {
            _ = try await ops.generalVPSStatus()
            XCTFail("a one-section answer must not parse")
        } catch {}
    }

    func testPingTunnelAlwaysRunsOnVPS() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("ping", stdout: "1 packets transmitted, 1 received, 0% packet loss")
        let ops = StatusOperations(runner: runner, config: makeConfig())

        _ = try await ops.pingTunnel()

        XCTAssertEqual(runner.calls.first?.host, .vps)
        XCTAssertEqual(runner.calls.first?.command, "ping -c 1 -W 2 '10.8.0.2'")
    }

    func testFailedCommandThrowsWithStderr() async {
        let runner = FakeSSHCommandRunner()
        runner.stub("wg show", exitCode: 1, stderr: "permission denied")
        let ops = StatusOperations(runner: runner, config: makeConfig())

        do {
            _ = try await ops.wgStatus(on: .vps)
            XCTFail("expected commandFailed")
        } catch let ServerControlError.commandFailed(_, exitCode, stderr) {
            XCTAssertEqual(exitCode, 1)
            XCTAssertEqual(stderr, "permission denied")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRebootIsFireAndForgetOnTheRequestedHost() async throws {
        let runner = FakeSSHCommandRunner()
        let ops = StatusOperations(runner: runner, config: makeConfig())

        try await ops.reboot(on: .home)

        XCTAssertEqual(runner.calls, [.init(kind: .fireAndForget,
                                            command: "sudo systemctl reboot",
                                            host: .home)])
    }

    func testControlContainerRunsTheWrapperOnTheRequestedHost() async throws {
        let runner = FakeSSHCommandRunner()
        let ops = StatusOperations(runner: runner, config: makeConfig())

        try await ops.controlContainer(.restart, name: "vaultwarden", on: .home)

        XCTAssertEqual(runner.calls, [.init(kind: .run,
                                            command: "sudo /opt/gryonixnexus-container-ctl.sh restart 'vaultwarden'",
                                            host: .home)])
    }
}

final class FullRestartOperationTests: XCTestCase {
    private func targets() -> [FullRestartOperation.ServiceRestartTarget] {
        [.init(name: "Mailcow", command: "sudo docker compose -p mailcowdockerized restart"),
         .init(name: "Vaultwarden", command: "sudo docker restart vaultwarden")]
    }

    /// The ORDER is the whole point
    func testRestartsInTopologyOrder() async throws {
        let runner = FakeSSHCommandRunner()
        let sleeper = FakeSleeper()
        runner.stub("mailcowdockerized restart")
        runner.stub("docker restart vaultwarden")
        runner.stub("systemctl restart wg-quick@wg0")   // home, fire-and-forget
        runner.stub("systemctl restart wg-quick@wg0")   // vps
        runner.stub("ping", stdout: "1 packets transmitted, 1 received")
        let op = FullRestartOperation(runner: runner, config: makeConfig(),
                                      services: targets(), sleeper: sleeper)

        var events: [FullRestartEvent] = []
        for try await event in op.run() { events.append(event) }

        XCTAssertEqual(events, [
            .restartingService(name: "Mailcow"),
            .serviceRestarted(name: "Mailcow"),
            .restartingService(name: "Vaultwarden"),
            .serviceRestarted(name: "Vaultwarden"),
            .restartSentToHomeTunnel,
            .restartingVPSTunnel,
            .vpsTunnelDone,
            .waitingForTunnel(attempt: 1, maxAttempts: FullRestartOperation.maxPollAttempts),
            .recovered,
        ])
        XCTAssertEqual(runner.calls.map(\.host), [.home, .home, .home, .vps, .vps])
        XCTAssertEqual(runner.calls[2].kind, .fireAndForget,
                       "the home tunnel restart cannot be awaited — it kills the session")
        XCTAssertEqual(runner.calls[3].kind, .run)
    }

    func testAFailingServiceDoesNotAbortTheRecovery() async throws {
        let runner = FakeSSHCommandRunner()
        let sleeper = FakeSleeper()
        runner.stub("mailcowdockerized restart", stdout: "", exitCode: 1)
        runner.stub("docker restart vaultwarden")
        runner.stub("systemctl restart wg-quick@wg0")
        runner.stub("systemctl restart wg-quick@wg0")
        runner.stub("ping", stdout: "1 packets transmitted, 1 received")
        let op = FullRestartOperation(runner: runner, config: makeConfig(),
                                      services: targets(), sleeper: sleeper)

        var events: [FullRestartEvent] = []
        for try await event in op.run() { events.append(event) }

        XCTAssertTrue(events.contains { if case .serviceFailed(let name, _) = $0 { return name == "Mailcow" } else { return false } })
        XCTAssertTrue(events.contains(.serviceRestarted(name: "Vaultwarden")), "the next service still runs")
        XCTAssertTrue(events.contains(.recovered))
    }
}

final class WireGuardRestartOperationTests: XCTestCase {
    func testHappyPath() async throws {
        let runner = FakeSSHCommandRunner()
        let sleeper = FakeSleeper()
        runner.stub("systemctl restart wg-quick@wg0")
        runner.stub("systemctl restart wg-quick@wg0")
        runner.stub("ping", stdout: "1 packets transmitted, 0 received", exitCode: 1)
        runner.stub("ping", stdout: "1 packets transmitted, 1 received")
        let op = WireGuardRestartOperation(runner: runner, config: makeConfig(), sleeper: sleeper)

        var events: [WGRestartEvent] = []
        for try await event in op.restartBoth() { events.append(event) }

        XCTAssertEqual(events.first, .restartingVPS)
        XCTAssertTrue(events.contains(.vpsDone))
        XCTAssertTrue(events.contains(.restartSentToHome))
        XCTAssertEqual(events.last, .recovered)
        // VPS restart awaited, home restart fire-and-forget, pings from VPS.
        XCTAssertEqual(runner.calls[0].kind, .run)
        XCTAssertEqual(runner.calls[0].host, .vps)
        XCTAssertEqual(runner.calls[1].kind, .fireAndForget)
        XCTAssertEqual(runner.calls[1].host, .home)
        XCTAssertTrue(runner.calls[2...].allSatisfy { $0.host == .vps && $0.kind == .run })
        XCTAssertEqual(sleeper.sleeps, [.seconds(3), .seconds(3)])
    }

    func testGivesUpAfterMaxAttempts() async throws {
        let runner = FakeSSHCommandRunner()
        runner.defaultResult = ExecResult(exitCode: 1,
                                          stdout: "1 packets transmitted, 0 received",
                                          stderr: "")
        // First two stubs: successful restarts; then default result = dead pings.
        runner.stub("wg-quick")
        runner.stub("wg-quick")
        let sleeper = FakeSleeper()
        let op = WireGuardRestartOperation(runner: runner, config: makeConfig(), sleeper: sleeper)

        var events: [WGRestartEvent] = []
        for try await event in op.restartBoth() { events.append(event) }

        XCTAssertEqual(events.last, .failedToRecover)
        XCTAssertEqual(sleeper.sleeps.count, WireGuardRestartOperation.maxPollAttempts)
    }
}

final class IdentityTests: XCTestCase {
    /// Fixture produced by `ssh-keygen -t ed25519 -C "gryonixnexus-app"`
    private let fixture = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    func testOpenSSHEncodingMatchesSSHKeygen() throws {
        let blobBase64 = fixture.split(separator: " ")[1]
        let blob = try XCTUnwrap(Data(base64Encoded: String(blobBase64)))
        let rawKey = blob.suffix(32)
        XCTAssertEqual(blob.count, 4 + 11 + 4 + 32)

        let encoded = OpenSSHPublicKey.encode(ed25519PublicKey: rawKey, comment: "gryonixnexus-app")

        XCTAssertEqual(encoded, fixture)
    }

    func testGeneratedIdentityRoundTrips() throws {
        let identity = AppSSHIdentity.generate()
        XCTAssertEqual(identity.privateKeySeed.count, 32)
        XCTAssertTrue(identity.publicKeyOpenSSH.hasPrefix("ssh-ed25519 "))
        XCTAssertTrue(identity.publicKeyOpenSSH.hasSuffix(" gryonixnexus-app"))

        let restored = try AppSSHIdentity(privateKeySeed: identity.privateKeySeed)
        XCTAssertEqual(restored.publicKeyOpenSSH, identity.publicKeyOpenSSH)
    }
}

final class SudoPasswordRequiredDetectionTests: XCTestCase {
    func testPasswordPromptBecomesSudoPasswordRequired() {
        let stderr = """
        sudo: a terminal is required to read the password; either use the -S \
        option to read from standard input or configure an askpass helper
        sudo: a password is required
        """
        let error = ServerControlError.commandFailure(
            command: "sudo docker compose -p mailcowdockerized stop",
            exitCode: 1, stderr: stderr)
        guard case .sudoPasswordRequired(let command) = error else {
            return XCTFail("expected sudoPasswordRequired, got \(error)")
        }
        XCTAssertEqual(command, "sudo docker compose -p mailcowdockerized stop")
    }

    func testOrdinaryFailureStaysCommandFailed() {
        let error = ServerControlError.commandFailure(
            command: "sudo docker ps", exitCode: 1,
            stderr: "Cannot connect to the Docker daemon")
        guard case .commandFailed = error else {
            return XCTFail("expected commandFailed, got \(error)")
        }
    }
}

final class AutoBackupSettingsTests: XCTestCase {
    func testParsesWrapperConfig() {
        let settings = AutoBackupOperations.parse("""
        SCHEDULE=every:2d@03:30
        RETENTION=5
        SERVICES='mailcow vaultwarden'
        """)
        XCTAssertEqual(settings.schedule, .days(count: 2, hour: 3, minute: 30))
        XCTAssertEqual(settings.retention, 5)
        XCTAssertEqual(settings.services, ["mailcow", "vaultwarden"])
        XCTAssertTrue(settings.isOn)
    }

    func testScheduleRoundTrips() {
        for schedule: CommandCatalog.Backups.Schedule in [
            .hours(count: 6, minute: 30),
            .hours(count: 1, minute: 0),
            .days(count: 1, hour: 3, minute: 0),
            .days(count: 14, hour: 23, minute: 59),
            .off
        ] {
            let encoded = schedule.wrapperArgument
            XCTAssertEqual(CommandCatalog.Backups.Schedule(wrapperArgument: encoded), schedule,
                           "round trip failed for \(encoded)")
        }
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertEqual(CommandCatalog.Backups.Schedule.hours(count: 0, minute: 0).wrapperArgument,
                       "every:1h@00:00")
        XCTAssertEqual(CommandCatalog.Backups.Schedule.hours(count: 99, minute: 90).wrapperArgument,
                       "every:23h@00:59")
        XCTAssertEqual(CommandCatalog.Backups.Schedule.days(count: 0, hour: 99, minute: -1).wrapperArgument,
                       "every:1d@23:00")
    }

    /// No file (older server, or never configured) — not an error
    func testEmptyOutputIsOff() {
        let settings = AutoBackupOperations.parse("")
        XCTAssertEqual(settings.schedule, .off)
        XCTAssertFalse(settings.isOn)
        XCTAssertTrue(settings.services.isEmpty)
    }

    /// Garbage values must not produce a nonsense schedule
    func testUnknownValuesFallBack() {
        let settings = AutoBackupOperations.parse("SCHEDULE=daily\nRETENTION=0\nSERVICES=''")
        XCTAssertEqual(settings.schedule, .off)
        XCTAssertEqual(settings.retention, 7)
        XCTAssertEqual(CommandCatalog.Backups.Schedule(wrapperArgument: "every:@"), .off)
        XCTAssertEqual(CommandCatalog.Backups.Schedule(wrapperArgument: "every:2x@03:00"), .off)
    }

    func testScheduleCommandLiterals() {
        XCTAssertEqual(CommandCatalog.Backups.controlScriptPath, "/opt/gryonixnexus-backup-ctl.sh")
        XCTAssertEqual(CommandCatalog.Backups.controlDoneMarker, "GRYONIXNEXUS_BACKUP_CTL_DONE")
        XCTAssertEqual(CommandCatalog.Backups.delete(path: "/opt/backups/mailcow/x.tar.gz"),
                       "sudo /opt/gryonixnexus-backup-ctl.sh delete '/opt/backups/mailcow/x.tar.gz'")
        XCTAssertEqual(CommandCatalog.Backups.setSchedule(.days(count: 7, hour: 4, minute: 0),
                                                          retention: 3, services: ["mailcow"]),
                       "sudo /opt/gryonixnexus-backup-ctl.sh set-schedule every:7d@04:00 3 mailcow")
        XCTAssertEqual(CommandCatalog.Backups.setSchedule(.hours(count: 6, minute: 30),
                                                          retention: 3, services: ["mailcow"]),
                       "sudo /opt/gryonixnexus-backup-ctl.sh set-schedule every:6h@00:30 3 mailcow")
        XCTAssertEqual(CommandCatalog.Backups.setSchedule(.off, retention: 7, services: []),
                       "sudo /opt/gryonixnexus-backup-ctl.sh set-schedule off 7")
    }
}

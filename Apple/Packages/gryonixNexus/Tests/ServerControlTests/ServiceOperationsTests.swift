import XCTest
import ServiceCatalog
@testable import ServerControl

final class ServiceOperationsTests: XCTestCase {
    private func deployment(topology: Topology = .vpsRelayWithHomeBackend,
                            services: Set<ServiceID> = [.mailcow, .vaultwarden]) -> Deployment {
        Deployment(
            name: "Test",
            topology: topology,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            homeWGAddress: topology == .vpsRelayWithHomeBackend ? "10.8.0.2" : nil,
            services: services
        )
    }

    private func ops(_ serviceID: ServiceID, runner: FakeSSHCommandRunner,
                     deployment: Deployment? = nil) throws -> ServiceOperations {
        let deployment = deployment ?? self.deployment()
        let service = try XCTUnwrap(ServiceRegistry.service(serviceID))
        return ServiceOperations(runner: runner, deployment: deployment, service: service,
                                 now: { Date(timeIntervalSince1970: 0) })
    }

    // MARK: - Status probes

    func testComposeProjectStatusRunsOnServicesHost() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p nextcloud ps", stdout: """
        NAME            IMAGE             COMMAND    SERVICE   CREATED       STATUS         PORTS
        nextcloud-app   nextcloud:apache  "apache"   app       2 hours ago   Up 2 hours     127.0.0.1:8081->80/tcp
        """)
        let deployment = deployment(services: [.mailcow, .nextcloud])

        let statuses = try await ops(.nextcloud, runner: runner, deployment: deployment).status()

        XCTAssertEqual(statuses.map(\.name), ["nextcloud-app"])
        XCTAssertEqual(statuses.first?.health, .ok)
        XCTAssertEqual(runner.calls, [.init(kind: .run,
                                            command: "sudo docker compose -p nextcloud ps",
                                            host: .home)])
    }

    func testSingleHostDeploymentRoutesToVPS() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p mailcowdockerized ps", stdout: """
        NAME       IMAGE   COMMAND   SERVICE   CREATED   STATUS    PORTS
        postfix    x       "x"       postfix   now       Up 1 h    25/tcp
        """)
        let single = deployment(topology: .singleHost, services: [.mailcow])

        _ = try await ops(.mailcow, runner: runner, deployment: single).status()

        XCTAssertEqual(runner.calls.first?.host, .vps)
    }

    func testContainerStatusFiltersClientSide() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker ps -a", stdout: """
        CONTAINER ID   IMAGE                       COMMAND       CREATED      STATUS                PORTS                    NAMES
        1a2b3c4d5e6f   vaultwarden/server:latest   "/start.sh"   3 weeks ago  Up 3 days (healthy)   127.0.0.1:8082->80/tcp   vaultwarden
        """)

        let statuses = try await ops(.vaultwarden, runner: runner).status()

        XCTAssertEqual(statuses.map(\.name), ["vaultwarden"])
        // sudoers matches the bare command — no --filter allowed.
        XCTAssertEqual(runner.calls.first?.command, "sudo docker ps -a")
    }

    // MARK: - Restart / update

    func testRestartUsesCatalogLiteral() async throws {
        let runner = FakeSSHCommandRunner()

        try await ops(.mailcow, runner: runner).restart()

        XCTAssertEqual(runner.calls.first?.command,
                       "sudo docker compose -p mailcowdockerized restart")
    }

    func testCapabilitiesReflectCatalog() throws {
        let runner = FakeSSHCommandRunner()
        XCTAssertEqual(try ops(.mailcow, runner: runner).backupKind, .wrapper)
        XCTAssertEqual(try ops(.vaultwarden, runner: runner).backupKind, .encrypted)
    }

    // MARK: - Logs

    func testLogsRunTheWhitelistedCommandOnTheServicesHost() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p mailcowdockerized logs",
                    stdout: "postfix-1  | ready\ndovecot-1  | ready\n")

        let lines = try await ops(.mailcow, runner: runner).logs()

        XCTAssertEqual(lines, ["postfix-1  | ready", "dovecot-1  | ready"])
        XCTAssertEqual(runner.calls.first?.command,
                       "sudo docker compose -p mailcowdockerized logs --tail 500 --timestamps")
        XCTAssertEqual(runner.calls.first?.host, .home)
    }

    func testLogsKeepStderr() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker logs", stdout: "on stdout", stderr: "on stderr")

        let lines = try await ops(.vaultwarden, runner: runner).logs()

        XCTAssertEqual(lines, ["on stdout", "on stderr"])
    }

    func testLogsSurfaceWhatDockerSaidOnFailure() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p mailcowdockerized logs", exitCode: 1,
                    stderr: "no such service: mailcow")

        let lines = try await ops(.mailcow, runner: runner).logs()

        XCTAssertEqual(lines, ["no such service: mailcow"])
    }

    // MARK: - Backups

    func testWrapperBackupGoesThroughTheSharedWrapperThenAsksForTheSize() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup mailcow",
                    stdout: "backing up...\nGRYONIXNEXUS_BACKUP_CTL_DONE\n")
        runner.stub("du -sh", stdout: "1.5G\t/opt/backups/mailcow/mailcow-x\n")

        let size = try await ops(.mailcow, runner: runner).runWrapperBackup()

        XCTAssertTrue(size.hasPrefix("1.5G"))
        XCTAssertTrue(runner.calls[1].command.contains(
            "sudo /opt/gryonixnexus-backup-ctl.sh backup mailcow --no-encrypt"),
            runner.calls[1].command)
        XCTAssertEqual(runner.calls[1].kind, .run, "the launch returns at once")
        XCTAssertTrue(runner.calls.contains { $0.kind == .stream },
                      "and the app then follows the job's log")
    }

    func testWrapperBackupWithoutTheMarkerThrows() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup", stdout: "tar: write error\n")

        do {
            _ = try await ops(.mailcow, runner: runner).runWrapperBackup()
            XCTFail("expected failure")
        } catch {
            // Expected: no completion marker.
        }
    }

    func testArchiveBackupReadsSizeAndPathFromTheMarkerLine() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup nextcloud", stdout: """
        GRYONIXNEXUS_BACKUP_DONE 4194304 /opt/backups/nextcloud/nextcloud-20260805-030000.tar.gz
        GRYONIXNEXUS_BACKUP_CTL_DONE
        """)

        let outcome = try await ops(.nextcloud, runner: runner).backup()

        XCTAssertEqual(outcome.sizeBytes, 4_194_304)
        XCTAssertEqual(outcome.path, "/opt/backups/nextcloud/nextcloud-20260805-030000.tar.gz")
        XCTAssertTrue(runner.calls[1].command.contains(
            "sudo /opt/gryonixnexus-backup-ctl.sh backup nextcloud --no-encrypt"),
            runner.calls[1].command)
    }

    func testVaultwardenWithoutAPasswordUsesTheServersStoredKey() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup vaultwarden", stdout: """
        GRYONIXNEXUS_BACKUP_DONE 2048 /opt/backups/vaultwarden/vaultwarden.20260805.gpg
        GRYONIXNEXUS_BACKUP_CTL_DONE
        """)

        let outcome = try await ops(.vaultwarden, runner: runner).backup()

        XCTAssertEqual(outcome.sizeBytes, 2048)
        XCTAssertTrue(runner.calls[1].command.contains(
            "sudo /opt/gryonixnexus-backup-ctl.sh backup vaultwarden --encrypt"),
            runner.calls[1].command)
        XCTAssertFalse(runner.calls.contains { $0.command.contains("docker stop") },
                       "the wrapper stops the container itself")
    }

    /// Encryption is a per-run choice for every service
    func testEncryptionDefaultComesFromTheSpecAndCanBeFlipped() async throws {
        XCTAssertFalse(try ops(.nextcloud, runner: FakeSSHCommandRunner()).backupEncryptsByDefault,
                       "a photo/file service must not pay for GPG unless asked")
        XCTAssertTrue(try ops(.vpnPanel, runner: FakeSSHCommandRunner()).backupEncryptsByDefault,
                      "the panel's stores are keys and password hashes")

        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("--encrypt", stdout: "GRYONIXNEXUS_BACKUP_CTL_DONE\n")
        runner.stub("du -sh")
        _ = try await ops(.nextcloud, runner: runner).backup(encrypt: true, passphrase: "secret")
        XCTAssertTrue(runner.calls[1].command.contains(
            "sudo /opt/gryonixnexus-backup-ctl.sh backup nextcloud --encrypt"),
            runner.calls[1].command)
    }

    func testEncryptedWrapperBackupPipesThePassphraseAndNeverLeaksIt() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup", stdout: "gpg: error\n")

        do {
            _ = try await ops(.vpnPanel, runner: runner).backup(passphrase: "topsecret")
            XCTFail("expected failure")
        } catch {
            XCTAssertFalse(String(describing: error).contains("topsecret"))
        }
        let launch = runner.calls.first { $0.command.contains("gryonixnexus-backup-ctl.sh backup") }
        let sent = try XCTUnwrap(launch?.command)
        XCTAssertTrue(sent.contains("cat ") && sent.contains(".pass"),
                      "the wrapper must read the secret from stdin: \(sent)")
        XCTAssertTrue(sent.contains("rm -f ") && sent.contains(".pass"),
                      "and the file must go before the run's own work begins: \(sent)")
        XCTAssertLessThan(sent.range(of: "rm -f ")!.lowerBound,
                          sent.range(of: "gryonixnexus-backup-ctl.sh")!.lowerBound,
                          "removed as the pipe is built, not after the backup has run")
        XCTAssertFalse(sent.contains("topsecret"), "the passphrase must stay out of argv: \(sent)")
        XCTAssertEqual(runner.fed, ["topsecret"])
        let follow = runner.calls.last?.command ?? ""
        XCTAssertFalse(follow.contains("topsecret"))
    }

    func testEstimateParsesBytesAndPinsTheCommand() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("estimate", stdout: """
        GRYONIXNEXUS_BACKUP_ESTIMATE 53687091200 10737418240
        GRYONIXNEXUS_BACKUP_CTL_DONE
        """)

        let estimate = try await ops(.immich, runner: runner).estimateBackup()

        XCTAssertEqual(estimate?.dataBytes, 53_687_091_200)
        XCTAssertEqual(estimate?.freeBytes, 10_737_418_240)
        XCTAssertEqual(estimate?.fitsOnDisk, false, "50 GiB of data, 10 GiB free")
        XCTAssertEqual(runner.calls.first?.command,
                       "sudo /opt/gryonixnexus-backup-ctl.sh estimate immich")
    }

    func testEstimateWithoutTheMarkerIsNil() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("estimate", stdout: "unsupported action: estimate\n")

        let estimate = try await ops(.forgejo, runner: runner).estimateBackup()
        XCTAssertNil(estimate)
    }

    func testListBackupsIncludesDirectoriesButHidesUploadStaging() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("ls -lht", stdout: """
        total 8.0K
        drwxr-xr-x 2 admin admin 4.0K Jul 20 03:00 mailcow-2026-07-20-03-00-00
        drwxr-xr-x 2 admin admin 4.0K Jul 19 12:00 incoming
        -rw-r--r-- 1 root  root  512M Jul 19 03:00 mailcow-2026-07-19.tar.gz
        """)

        let entries = try await ops(.mailcow, runner: runner).listBackups()

        XCTAssertEqual(entries.map(\.name),
                       ["mailcow-2026-07-20-03-00-00", "mailcow-2026-07-19.tar.gz"])
    }

    func testLatestShareableBackupPathPinsCommandAndParsesResult() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("ls -1dt", stdout: "/opt/backups/vaultwarden/vaultwarden-20260719.tar.gz.gpg\n")

        let path = try await ops(.vaultwarden, runner: runner).latestShareableBackupPath()

        XCTAssertEqual(path, "/opt/backups/vaultwarden/vaultwarden-20260719.tar.gz.gpg")
        XCTAssertEqual(runner.calls.first?.command,
                       "f=\"$(ls -1dt /opt/backups/vaultwarden/* 2>/dev/null | head -n 1)\"; { [ -f \"$f\" ] && [ -r \"$f\" ] && printf '%s\\n' \"$f\"; } || true")
        XCTAssertEqual(runner.calls.first?.host, .home)
    }

    func testLatestShareableBackupPathEmptyOutputMeansNil() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("ls -1dt", stdout: "\n")

        let path = try await ops(.mailcow, runner: runner).latestShareableBackupPath()

        XCTAssertNil(path)
    }

    func testFailedEncryptionRemovesThePlainVaultArchive() async throws {
        let runner = FakeSSHCommandRunner()
        for match in ["mkdir", "docker stop", "tar czf", "chown"] { runner.stub(match) }
        runner.stub("gpg", exitCode: 2, stderr: "gpg: error")

        do {
            for try await _ in try ops(.vaultwarden, runner: runner).encryptedBackup(passphrase: "pw") {}
            XCTFail("expected failure")
        } catch {}

        let commands = runner.calls.map(\.command)
        XCTAssertTrue(commands.contains("rm -f '/opt/backups/vaultwarden/vaultwarden-backup.tar.gz'"))
        XCTAssertFalse(commands.contains { $0.contains("pw'") || $0.contains("--passphrase ") })
        XCTAssertEqual(runner.fed, ["pw"])
    }

    func testEncryptedBackupRestartsContainerOnFailure() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("docker stop vaultwarden")
        runner.stub("tar czf", exitCode: 2, stderr: "disk full")

        var events: [VWBackupEvent] = []
        do {
            for try await event in try ops(.vaultwarden, runner: runner).encryptedBackup(passphrase: "secret") {
                events.append(event)
            }
            XCTFail("expected failure")
        } catch {
            // Expected: the tar step failed.
        }

        let commands = runner.calls.map(\.command)
        XCTAssertTrue(commands.contains("sudo docker start vaultwarden"),
                      "container must be started again even after a failed step")
        XCTAssertEqual(events.last, .startingContainer)
    }

    func testEncryptedBackupNeverLeaksPassphrase() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("docker stop")
        runner.stub("tar czf")
        runner.stub("chown")
        runner.stub("gpg", exitCode: 2, stderr: "gpg: error")

        do {
            for try await _ in try ops(.vaultwarden, runner: runner).encryptedBackup(passphrase: "topsecret") {}
            XCTFail("expected failure")
        } catch {
            XCTAssertFalse(String(describing: error).contains("topsecret"))
        }
    }

    func testEncryptedBackupChownsToDeploymentUser() async throws {
        let runner = FakeSSHCommandRunner()
        for match in ["mkdir", "docker stop", "tar czf", "chown", "gpg", "rm -f",
                      "docker start", "du -sh", "ls -1t"] {
            runner.stub(match)
        }

        for try await _ in try ops(.vaultwarden, runner: runner).encryptedBackup(passphrase: "p") {}

        XCTAssertTrue(runner.calls.map(\.command).contains(
            "sudo chown 'admin' '/opt/backups/vaultwarden/vaultwarden-backup.tar.gz'"
        ), "chown must use the deployment's ssh user (the sudoers literal)")
    }

    // MARK: - Uninstall

    func testUninstallRunsWrapperAndChecksMarker() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("gryonixnexus-uninstall.sh",
                    stdout: "removing containers...\nGRYONIXNEXUS_UNINSTALL_DONE\n")
        let ops = ServiceOperations(runner: runner, deployment: deployment(),
                                    service: MailcowService())
        _ = try await ops.uninstall(purge: .none)
        XCTAssertTrue(runner.calls.first?.command.contains("sudo /opt/gryonixnexus-uninstall.sh mailcow") == true,
                      runner.calls.first?.command ?? "")
        XCTAssertEqual(runner.calls.first?.kind, .run)
    }

    func testUninstallPurgeAppendsFlag() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("", stdout: "GRYONIXNEXUS_UNINSTALL_DONE\n")
        let ops = ServiceOperations(runner: runner, deployment: deployment(),
                                    service: VaultwardenService())
        _ = try await ops.uninstall(purge: PurgeOptions(data: true))
        XCTAssertTrue(runner.calls.first?.command.contains(
            "sudo /opt/gryonixnexus-uninstall.sh vaultwarden --purge-data") == true,
            runner.calls.first?.command ?? "")
    }

    /// The VPN protocols and the panel share one wrapper target
    func testUninstallVPNProtocolsMapToSharedTarget() {
        let deployment = deployment(services: [.xrayReality, .vpnPanel])
        for service in [XrayRealityService() as any ManagedService, VPNPanelService()] {
            let ops = ServiceOperations(runner: FakeSSHCommandRunner(),
                                        deployment: deployment, service: service)
            XCTAssertEqual(ops.uninstallTarget, "vpn")
        }
    }

    func testUninstallWithoutMarkerThrows() async {
        let runner = FakeSSHCommandRunner()
        runner.stub("", stdout: "removing containers...\n")
        let ops = ServiceOperations(runner: runner, deployment: deployment(),
                                    service: MailcowService())
        do {
            _ = try await ops.uninstall(purge: .none)
            XCTFail("expected commandFailed")
        } catch {
            guard case ServerControlError.commandFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    // MARK: - What a status MEANS

    func testAContainerThatIsNotThereIsNotHealthy() {
        XCTAssertEqual(ContainerStatus(name: "x", status: "not running").health, .warning)
        XCTAssertEqual(ContainerStatus(name: "x", status: "No such container: x").health, .warning)
    }

    func testComposeStillReadsAsRunning() {
        XCTAssertEqual(ContainerStatus(name: "x", status: "running").health, .ok)
        XCTAssertEqual(ContainerStatus(name: "x", status: "running (healthy)").health, .ok)
    }

    func testTheStatusesDockerReallyPrints() {
        XCTAssertEqual(ContainerStatus(name: "x", status: "Up 2 hours").health, .ok)
        XCTAssertEqual(ContainerStatus(name: "x", status: "Up 3 minutes (healthy)").health, .ok)
        XCTAssertEqual(ContainerStatus(name: "x", status: "Up 3 hours (unhealthy)").health, .critical)
        XCTAssertEqual(ContainerStatus(name: "x", status: "Exited (0) 3 days ago").health, .critical)
        XCTAssertEqual(ContainerStatus(name: "x", status: "Created").health, .warning)
        XCTAssertEqual(ContainerStatus(name: "x", status: "Restarting (1) 5 seconds ago").health, .warning)
    }
}

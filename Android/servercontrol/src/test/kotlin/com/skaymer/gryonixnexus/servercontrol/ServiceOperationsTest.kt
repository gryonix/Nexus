package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import java.time.Instant
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.test.assertFailsWith

class ServiceOperationsTest {
    private fun deployment(
        topology: Topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        services: Set<ServiceID> = setOf(ServiceID.MAILCOW, ServiceID.VAULTWARDEN),
    ) = Deployment(
        id = "11111111-1111-1111-1111-111111111111",
        name = "Test",
        topology = topology,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.4", user = "admin"),
        homeWGAddress = if (topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) "10.8.0.2" else null,
        services = services,
    )

    private fun ops(
        serviceID: ServiceID,
        runner: FakeSSHCommandRunner,
        deployment: Deployment = deployment(),
    ): ServiceOperations {
        val service = checkNotNull(ServiceRegistry.service(serviceID)) { "unknown service $serviceID" }
        return ServiceOperations(runner, deployment, service, now = { Instant.EPOCH })
    }

    private fun service(id: ServiceID): ManagedService = checkNotNull(ServiceRegistry.service(id))

    // -------------------------------------------------------- Status probes

    @Test
    fun `a compose project is probed on the machine that runs services`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "docker compose -p nextcloud ps",
            stdout = """
            NAME            IMAGE             COMMAND    SERVICE   CREATED       STATUS         PORTS
            nextcloud-app   nextcloud:apache  "apache"   app       2 hours ago   Up 2 hours     127.0.0.1:8081->80/tcp
            """.trimIndent(),
        )
        val deployment = deployment(services = setOf(ServiceID.MAILCOW, ServiceID.NEXTCLOUD))

        val statuses = ops(ServiceID.NEXTCLOUD, runner, deployment).status()

        assertEquals(listOf("nextcloud-app"), statuses.map { it.name })
        assertEquals(HealthLevel.OK, statuses.first().health)
        assertEquals(
            listOf(
                FakeSSHCommandRunner.Call(
                    FakeSSHCommandRunner.CallKind.RUN,
                    "sudo docker compose -p nextcloud ps",
                    SSHHostID.HOME,
                ),
            ),
            runner.calls,
        )
    }

    @Test
    fun `a single-host deployment routes to the entry machine`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "docker compose -p mailcowdockerized ps",
            stdout = """
            NAME       IMAGE   COMMAND   SERVICE   CREATED   STATUS    PORTS
            postfix    x       "x"       postfix   now       Up 1 h    25/tcp
            """.trimIndent(),
        )
        val single = deployment(topology = Topology.SINGLE_HOST, services = setOf(ServiceID.MAILCOW))

        ops(ServiceID.MAILCOW, runner, single).status()

        assertEquals(SSHHostID.VPS, runner.calls.first().host)
    }

    @Test
    fun `a container probe filters client-side`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "docker ps -a",
            stdout = """
            CONTAINER ID   IMAGE                       COMMAND       CREATED      STATUS                PORTS                    NAMES
            1a2b3c4d5e6f   vaultwarden/server:latest   "/start.sh"   3 weeks ago  Up 3 days (healthy)   127.0.0.1:8082->80/tcp   vaultwarden
            """.trimIndent(),
        )

        val statuses = ops(ServiceID.VAULTWARDEN, runner).status()

        assertEquals(listOf("vaultwarden"), statuses.map { it.name })
        // sudoers matches the bare command — no --filter allowed.
        assertEquals("sudo docker ps -a", runner.calls.first().command)
    }

    @Test
    fun `a container docker does not list reads as not running`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "docker ps -a",
            stdout = """
            CONTAINER ID   IMAGE     COMMAND       CREATED      STATUS       PORTS   NAMES
            1a2b3c4d5e6f   nginx     "/start.sh"   3 weeks ago  Up 3 days            something-else
            """.trimIndent(),
        )

        val statuses = ops(ServiceID.VAULTWARDEN, runner).status()

        assertEquals(listOf("vaultwarden"), statuses.map { it.name })
        assertEquals("not running", statuses.first().status)
        assertEquals(HealthLevel.WARNING, statuses.first().health, "what Swift answers too")
    }

    // ------------------------------------------------------ Restart / update

    @Test
    fun `restart sends the catalog literal`() = runTest {
        val runner = FakeSSHCommandRunner()

        ops(ServiceID.MAILCOW, runner).restart()

        assertEquals(
            "sudo docker compose -p mailcowdockerized restart",
            runner.calls.first().command,
        )
    }

    @Test
    fun `the capabilities are read from the catalog`() {
        val runner = FakeSSHCommandRunner()
        assertEquals(ServiceOperations.BackupKind.WRAPPER, ops(ServiceID.MAILCOW, runner).backupKind)
        assertEquals(
            ServiceOperations.BackupKind.ENCRYPTED,
            ops(ServiceID.VAULTWARDEN, runner).backupKind,
        )
    }

    @Test
    fun `only a compose-pull service may be updated from the dashboard`() {
        val runner = FakeSSHCommandRunner()
        assertTrue(ops(ServiceID.NEXTCLOUD, runner).canUpdate)
        assertFalse(ops(ServiceID.MAILCOW, runner).canUpdate, "mailcow ships its own updater")
    }

    // ------------------------------------------------------------------ Logs

    @Test
    fun `logs run the whitelisted command on the services host`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "docker compose -p mailcowdockerized logs",
            stdout = "postfix-1  | ready\ndovecot-1  | ready\n",
        )

        val lines = ops(ServiceID.MAILCOW, runner).logs()

        assertEquals(listOf("postfix-1  | ready", "dovecot-1  | ready"), lines)
        assertEquals(
            "sudo docker compose -p mailcowdockerized logs --tail 500 --timestamps",
            runner.calls.first().command,
        )
        assertEquals(SSHHostID.HOME, runner.calls.first().host)
    }

    @Test
    fun `logs keep stderr`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("docker logs", stdout = "on stdout", stderr = "on stderr")

        assertEquals(listOf("on stdout", "on stderr"), ops(ServiceID.VAULTWARDEN, runner).logs())
    }

    @Test
    fun `logs surface what docker said on failure`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "docker compose -p mailcowdockerized logs",
            exitCode = 1,
            stderr = "no such service: mailcow",
        )

        assertEquals(listOf("no such service: mailcow"), ops(ServiceID.MAILCOW, runner).logs())
    }

    // --------------------------------------------------------------- Backups

    @Test
    fun `a wrapper backup goes through the shared wrapper and then asks for the size`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub(
            "gryonixnexus-backup-ctl.sh backup mailcow",
            stdout = "backing up...\nGRYONIXNEXUS_BACKUP_CTL_DONE\n",
        )
        runner.stub("du -sh", stdout = "1.5G\t/opt/backups/mailcow/mailcow-x\n")

        val size = ops(ServiceID.MAILCOW, runner).runWrapperBackup()

        assertTrue(size.startsWith("1.5G"))
        assertTrue(runner.calls[1].command.contains("sudo /opt/gryonixnexus-backup-ctl.sh backup mailcow --no-encrypt"), runner.calls[1].command)
        assertEquals(
            FakeSSHCommandRunner.CallKind.RUN,
            runner.calls[1].kind,
            "the launch returns at once — the run belongs to the host now",
        )
        assertTrue(
            runner.calls.any { it.kind == FakeSSHCommandRunner.CallKind.STREAM },
            "and the app follows the job's log afterwards",
        )
    }

    @Test
    fun `a wrapper backup without the marker throws`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup", stdout = "tar: write error\n")

        assertFailsWith<ServerControlError> { ops(ServiceID.MAILCOW, runner).runWrapperBackup() }
    }

    @Test
    fun `an archive backup reads size and path from the marker line`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub(
            "gryonixnexus-backup-ctl.sh backup nextcloud",
            stdout = """
            GRYONIXNEXUS_BACKUP_DONE 4194304 /opt/backups/nextcloud/nextcloud-20260805-030000.tar.gz
            GRYONIXNEXUS_BACKUP_CTL_DONE
            """.trimIndent(),
        )

        val outcome = ops(ServiceID.NEXTCLOUD, runner).backup()

        assertEquals(4_194_304L, outcome.sizeBytes)
        assertEquals("/opt/backups/nextcloud/nextcloud-20260805-030000.tar.gz", outcome.path)
        assertTrue(runner.calls[1].command.contains("sudo /opt/gryonixnexus-backup-ctl.sh backup nextcloud --no-encrypt"), runner.calls[1].command)
    }

    @Test
    fun `vaultwarden without a password uses the server's stored key`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub(
            "gryonixnexus-backup-ctl.sh backup vaultwarden",
            stdout = "GRYONIXNEXUS_BACKUP_DONE 2048 /opt/backups/vaultwarden/vaultwarden.20260805.gpg\nGRYONIXNEXUS_BACKUP_CTL_DONE\n",
        )

        val outcome = ops(ServiceID.VAULTWARDEN, runner).backup()

        assertEquals(2048L, outcome.sizeBytes)
        assertTrue(
            runner.calls[1].command.contains("sudo /opt/gryonixnexus-backup-ctl.sh backup vaultwarden --encrypt"),
            runner.calls[1].command,
        )
        assertFalse(runner.calls.any { it.command.contains("docker stop") }, "the wrapper stops the container itself")
    }

    /** Encryption is a per-run choice for every service */
    @Test
    fun `the encryption default comes from the spec and can be flipped`() = runTest {
        assertFalse(
            ops(ServiceID.NEXTCLOUD, FakeSSHCommandRunner()).backupEncryptsByDefault,
            "a photo/file service must not pay for GPG unless asked",
        )
        assertTrue(
            ops(ServiceID.VPN_PANEL, FakeSSHCommandRunner()).backupEncryptsByDefault,
            "the panel's stores are keys and password hashes",
        )

        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("--encrypt", stdout = "GRYONIXNEXUS_BACKUP_CTL_DONE\n")
        runner.stub("du -sh")
        ops(ServiceID.NEXTCLOUD, runner).backup(encrypt = true, passphrase = "secret")
        assertTrue(
            runner.calls[1].command.contains(
                "sudo /opt/gryonixnexus-backup-ctl.sh backup nextcloud --encrypt",
            ),
            runner.calls[1].command,
        )
    }

    @Test
    fun `an encrypted wrapper backup pipes the passphrase and never leaks it`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("gryonixnexus-backup-ctl.sh backup", stdout = "gpg: error\n")

        val error = assertFailsWith<ServerControlError> {
            ops(ServiceID.VPN_PANEL, runner).backup(passphrase = "topsecret")
        }
        assertFalse(error.toString().contains("topsecret"))

        val sent = runner.calls[1].command
        assertTrue(sent.contains("cat ") && sent.contains(".pass"),
            "the wrapper must read the secret from stdin: ${'$'}sent")
        assertTrue(sent.indexOf("rm -f ") < sent.indexOf("gryonixnexus-backup-ctl.sh"),
            "removed as the pipe is built, not after the backup has run: ${'$'}sent")
        assertFalse(sent.contains("topsecret"), "the passphrase must stay out of argv")
        assertEquals(listOf("topsecret"), runner.fed)
    }

    @Test
    fun `the estimate parses bytes and pins the command`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "estimate",
            stdout = """
            GRYONIXNEXUS_BACKUP_ESTIMATE 53687091200 10737418240
            GRYONIXNEXUS_BACKUP_CTL_DONE
            """.trimIndent(),
        )

        val estimate = ops(ServiceID.IMMICH, runner).estimateBackup()

        assertEquals(53_687_091_200L, estimate?.dataBytes)
        assertEquals(10_737_418_240L, estimate?.freeBytes)
        assertEquals(false, estimate?.fitsOnDisk, "50 GiB of data, 10 GiB free")
        assertEquals("sudo /opt/gryonixnexus-backup-ctl.sh estimate immich", runner.calls.first().command)
    }

    @Test
    fun `an estimate without the marker is null`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("estimate", stdout = "unsupported action: estimate\n")

        assertNull(ops(ServiceID.FORGEJO, runner).estimateBackup())
    }

    @Test
    fun `the listing includes directories but hides the upload staging`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "ls -lht",
            stdout = """
            total 8.0K
            drwxr-xr-x 2 admin admin 4.0K Jul 20 03:00 mailcow-2026-07-20-03-00-00
            drwxr-xr-x 2 admin admin 4.0K Jul 19 12:00 incoming
            -rw-r--r-- 1 root  root  512M Jul 19 03:00 mailcow-2026-07-19.tar.gz
            """.trimIndent(),
        )

        val entries = ops(ServiceID.MAILCOW, runner).listBackups()

        assertEquals(
            listOf("mailcow-2026-07-20-03-00-00", "mailcow-2026-07-19.tar.gz"),
            entries.map { it.name },
        )
    }

    @Test
    fun `the shareable path is pinned and parsed`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("ls -1dt", stdout = "/opt/backups/vaultwarden/vaultwarden-20260719.tar.gz.gpg\n")

        val path = ops(ServiceID.VAULTWARDEN, runner).latestShareableBackupPath()

        assertEquals("/opt/backups/vaultwarden/vaultwarden-20260719.tar.gz.gpg", path)
        assertEquals(
            "f=\"\$(ls -1dt /opt/backups/vaultwarden/* 2>/dev/null | head -n 1)\"; " +
                "{ [ -f \"\$f\" ] && [ -r \"\$f\" ] && printf '%s\\n' \"\$f\"; } || true",
            runner.calls.first().command,
        )
        assertEquals(SSHHostID.HOME, runner.calls.first().host)
    }

    @Test
    fun `empty output means there is nothing to share`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("ls -1dt", stdout = "\n")

        assertNull(ops(ServiceID.MAILCOW, runner).latestShareableBackupPath())
    }

    @Test
    fun `an encrypted backup starts the container again after a failed step`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("docker stop vaultwarden")
        runner.stub("tar czf", exitCode = 2, stderr = "disk full")

        val events = mutableListOf<VWBackupEvent>()
        assertFailsWith<ServerControlError> {
            ops(ServiceID.VAULTWARDEN, runner).encryptedBackup("secret").collect { events += it }
        }

        assertTrue(
            runner.calls.map { it.command }.contains("sudo docker start vaultwarden"),
            "container must be started again even after a failed step",
        )
        assertEquals(VWBackupEvent.StartingContainer, events.last())
    }

    @Test
    fun `an encrypted backup never leaks the passphrase`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("mkdir")
        runner.stub("docker stop")
        runner.stub("tar czf")
        runner.stub("chown")
        runner.stub("gpg", exitCode = 2, stderr = "gpg: error")

        val error = assertFailsWith<ServerControlError> {
            ops(ServiceID.VAULTWARDEN, runner).encryptedBackup("topsecret").toList()
        }
        assertFalse(error.toString().contains("topsecret"))
    }

    @Test
    fun `an encrypted backup chowns to the deployment user`() = runTest {
        val runner = FakeSSHCommandRunner()
        for (match in listOf(
            "mkdir", "docker stop", "tar czf", "chown", "gpg", "rm -f",
            "docker start", "du -sh", "ls -1t",
        )) {
            runner.stub(match)
        }

        ops(ServiceID.VAULTWARDEN, runner).encryptedBackup("p").toList()

        assertTrue(
            runner.calls.map { it.command }.contains(
                "sudo chown 'admin' '/opt/backups/vaultwarden/vaultwarden-backup.tar.gz'",
            ),
            "chown must use the deployment's ssh user (the sudoers literal)",
        )
    }

    @Test
    fun `the encrypted archive is named from the injected clock, in UTC`() = runTest {
        val runner = FakeSSHCommandRunner()
        for (match in listOf(
            "mkdir", "docker stop", "tar czf", "chown", "gpg", "rm -f",
            "docker start", "du -sh", "ls -1t",
        )) {
            runner.stub(match)
        }

        ops(ServiceID.VAULTWARDEN, runner).encryptedBackup("p").toList()

        assertTrue(
            runner.calls.map { it.command }.any {
                it.contains("/opt/backups/vaultwarden/vaultwarden-19700101-000000.tar.gz.gpg")
            },
            "the epoch must format as 19700101-000000 — UTC, not the test machine's zone",
        )
    }

    // ------------------------------------------------------------- Uninstall

    @Test
    fun `uninstall runs the wrapper and checks the marker`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "gryonixnexus-uninstall.sh",
            stdout = "removing containers...\nGRYONIXNEXUS_UNINSTALL_DONE\n",
        )
        val operations = ServiceOperations(runner, deployment(), service(ServiceID.MAILCOW))

        operations.uninstall(PurgeOptions.NONE)

        assertTrue(
            runner.calls.first().command.contains("sudo /opt/gryonixnexus-uninstall.sh mailcow"),
            runner.calls.first().command,
        )
        assertEquals(FakeSSHCommandRunner.CallKind.RUN, runner.calls.first().kind)
    }

    @Test
    fun `a purge appends its flag`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("", stdout = "GRYONIXNEXUS_UNINSTALL_DONE\n")
        val operations = ServiceOperations(runner, deployment(), service(ServiceID.VAULTWARDEN))

        operations.uninstall(PurgeOptions(data = true))

        assertTrue(
            runner.calls.first().command.contains(
                "sudo /opt/gryonixnexus-uninstall.sh vaultwarden --purge-data",
            ),
            runner.calls.first().command,
        )
    }

    /** The VPN protocols and the panel share one wrapper target */
    @Test
    fun `the VPN protocols map to the shared uninstall target`() {
        val deployment = deployment(services = setOf(ServiceID.XRAY_REALITY, ServiceID.VPN_PANEL))
        for (id in listOf(ServiceID.XRAY_REALITY, ServiceID.VPN_PANEL)) {
            val operations = ServiceOperations(FakeSSHCommandRunner(), deployment, service(id))
            assertEquals("vpn", operations.uninstallTarget)
        }
    }

    @Test
    fun `an uninstall without the marker throws`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("", stdout = "removing containers...\n")
        val operations = ServiceOperations(runner, deployment(), service(ServiceID.MAILCOW))

        assertFailsWith<ServerControlError.CommandFailed> {
            operations.uninstall(PurgeOptions.NONE)
        }
    }

    // --------------------------------------------------------------- Uploads

    @Test
    fun `an uploaded name cannot become a path`() {
        assertEquals("x.tar.gz", ServiceOperations.sanitizedUploadName("../../etc/x.tar.gz"))
        assertEquals("a.b.gz", ServiceOperations.sanitizedUploadName("a..b.gz"))
        assertEquals("upload.tar.gz", ServiceOperations.sanitizedUploadName("/"))
        assertEquals("backup.tar.gz", ServiceOperations.sanitizedUploadName("bac kup.tar.gz"))
    }

    // ------------------------------------------------ What a status MEANS

    @Test
    fun `a container that is not there is not healthy`() {
        assertEquals(HealthLevel.WARNING, ContainerStatus("x", "not running").health)
        assertEquals(HealthLevel.WARNING, ContainerStatus("x", "No such container: x").health)
    }

    @Test
    fun `compose still reads as running`() {
        assertEquals(HealthLevel.OK, ContainerStatus("x", "running").health)
        assertEquals(HealthLevel.OK, ContainerStatus("x", "running (healthy)").health)
    }

    @Test
    fun `the statuses docker really prints`() {
        assertEquals(HealthLevel.OK, ContainerStatus("x", "Up 2 hours").health)
        assertEquals(HealthLevel.OK, ContainerStatus("x", "Up 3 minutes (healthy)").health)
        assertEquals(HealthLevel.CRITICAL, ContainerStatus("x", "Up 3 hours (unhealthy)").health)
        assertEquals(HealthLevel.CRITICAL, ContainerStatus("x", "Exited (0) 3 days ago").health)
        assertEquals(HealthLevel.WARNING, ContainerStatus("x", "Created").health)
        assertEquals(HealthLevel.WARNING, ContainerStatus("x", "Restarting (1) 5 seconds ago").health)
    }

    @Test
    fun `a value with a space or a quote cannot run extra shell`() {
        assertEquals(
            "sudo docker restart 'vault warden; reboot'",
            CommandCatalog.Vaultwarden.restart("vault warden; reboot"),
        )
        assertEquals(
            "cd '/opt/my mail' && sudo /bin/bash '/opt/my mail/update.sh' --force",
            CommandCatalog.Mailcow.update("/opt/my mail"),
        )
        assertEquals("ls -lht '/b/it'\\''s'/*.gpg", CommandCatalog.Backups.listVaultwarden("/b/it's"))
    }
}

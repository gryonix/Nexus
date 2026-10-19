package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class StatusOperationsTest {
    private val config = DashboardConfig(
        vpsHost = "203.0.113.4",
        sshUser = "admin",
        homeWGAddress = "10.8.0.2",
    )

    private fun ops(runner: FakeSSHCommandRunner) = StatusOperations(runner, config)

    @Test
    fun `the general probe splits into its three sections`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "sysctl",
            stdout = listOf(
                "net.ipv4.ip_forward = 1",
                "4 packets transmitted, 4 received, 0% packet loss",
                "4 packets transmitted, 0 received, 100% packet loss",
            ).joinToString("\n${CommandCatalog.GENERAL_PROBE_SEPARATOR}\n"),
        )

        val status = ops(runner).generalVPSStatus()

        assertTrue(status.forwarding)
        assertTrue(status.selfPing.isAlive)
        assertFalse(status.tunnelPing.isAlive, "the tunnel is the half that is down")
        assertEquals(SSHHostID.VPS, runner.calls.first().host)
    }

    @Test
    fun `a probe that comes back in the wrong shape is a parse failure`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("sysctl", stdout = "net.ipv4.ip_forward = 1")
        assertFailsWith<ServerControlError.ParseFailure> { ops(runner).generalVPSStatus() }
    }

    @Test
    fun `the lockdown answer is read off the wrapper's last line`() {
        assertEquals(AdminLockdownState.All, StatusOperations.parseLockdownAnswer("reloading\non\n"))
        assertEquals(AdminLockdownState.Off, StatusOperations.parseLockdownAnswer("off\n"))
        assertEquals(
            AdminLockdownState.Only(setOf("admin.example.com", "vault.example.com")),
            StatusOperations.parseLockdownAnswer("only admin.example.com vault.example.com\n"),
        )
    }

    /**
     * An `only` naming nothing usable is OFF, not "guarding an empty list" —
     * the wrapper does not know the site set, so an empty list has no other
     * honest reading.
     */
    @Test
    fun `an only list with nothing valid in it reads as off`() {
        assertEquals(AdminLockdownState.Off, StatusOperations.parseLockdownAnswer("only \$(rm -rf)\n"))
        assertEquals(AdminLockdownState.Off, StatusOperations.parseLockdownAnswer("something else\n"))
    }

    @Test
    fun `guards answers per vhost`() {
        assertTrue(AdminLockdownState.All.guards("admin.example.com"))
        assertFalse(AdminLockdownState.Off.guards("admin.example.com"))
        val only = AdminLockdownState.Only(setOf("admin.example.com"))
        assertTrue(only.guards("admin.example.com"))
        assertFalse(only.guards("vault.example.com"))
    }

    /** An empty list means "off" — and that is sent as the off verb, not as `only`. */
    @Test
    fun `setting an empty host list turns the guard off`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("admin-lockdown.sh off", stdout = "off\n")

        val state = ops(runner).setAdminLockdown(emptyList(), SSHHostID.VPS)

        assertEquals(AdminLockdownState.Off, state)
        assertEquals("sudo /opt/gryonixnexus-admin-lockdown.sh off", runner.calls.first().command)
    }

    /**
     * A reboot tears down the SSH connection before an exit status could ever
     * come back, so it must not be awaited as a normal command.
     */
    @Test
    fun `a reboot is fire-and-forget`() = runTest {
        val runner = FakeSSHCommandRunner()
        ops(runner).reboot(SSHHostID.HOME)
        assertEquals(FakeSSHCommandRunner.CallKind.FIRE_AND_FORGET, runner.calls.first().kind)
        assertEquals("sudo systemctl reboot", runner.calls.first().command)
    }

    @Test
    fun `restarting sshd touches both machines`() = runTest {
        val runner = FakeSSHCommandRunner()
        ops(runner).restartSSHDBoth()
        assertEquals(
            setOf(SSHHostID.VPS, SSHHostID.HOME),
            runner.calls.map { it.host }.toSet(),
        )
    }

    @Test
    fun `a container is controlled through the root-owned wrapper`() = runTest {
        val runner = FakeSSHCommandRunner()
        ops(runner).controlContainer(
            CommandCatalog.Containers.Action.RESTART,
            "nextcloud-app",
            SSHHostID.HOME,
        )
        assertEquals(
            "sudo /opt/gryonixnexus-container-ctl.sh restart 'nextcloud-app'",
            runner.calls.first().command,
        )
    }
}

class UninstallOperationsTest {
    private fun pair() = Deployment(
        id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        homeWGAddress = "10.8.0.2",
        services = setOf(ServiceID.NEXTCLOUD),
    )

    /**
     * **The one ordering that cannot be retried.** Clean the relay first and
     * the home half is stranded with its services and control user still on it
     * — the only way to finish is the provider's console.
     */
    @Test
    fun `the home half is cleaned before the machine it is reached through`() {
        assertEquals(
            listOf(SSHHostID.HOME, SSHHostID.VPS),
            UninstallOperations(FakeSSHCommandRunner(), pair()).hosts,
        )
    }

    @Test
    fun `each host must show the wrapper's own marker`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("uninstall.sh --all", stdout = "cleaning…\nGRYONIXNEXUS_UNINSTALL_DONE\n")
        runner.stub("uninstall.sh --all", stdout = "cleaning…\nGRYONIXNEXUS_UNINSTALL_DONE\n")

        val events = mutableListOf<UninstallOperations.Event>()
        UninstallOperations(runner, pair()).fullCleanup(PurgeOptions.NONE) { events += it }

        assertEquals(listOf(SSHHostID.HOME, SSHHostID.VPS), runner.calls.map { it.host }.distinct())
        assertEquals(
            listOf(SSHHostID.HOME, SSHHostID.VPS),
            events.filterIsInstance<UninstallOperations.Event.HostFinished>().map { it.host },
        )
    }

    /** No marker — the wrapper died halfway through; never report success. */
    @Test
    fun `a host that shows no marker fails the cleanup`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("uninstall.sh --all", stdout = "cleaning…\n")
        assertFailsWith<ServerControlError> {
            UninstallOperations(runner, pair()).fullCleanup(PurgeOptions.NONE) {}
        }
    }
}

/**
 * Every routing decision in one place, each stating BOTH answers — a fixture on
 * which the two branches agree proves nothing about either.
 */
class OperationRoutingTest {
    @Test
    fun `the encrypted-volume backup never leaves the SSH path`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            BackupRouting.route(true, true, ServiceOperations.BackupKind.WRAPPER),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            BackupRouting.route(true, true, ServiceOperations.BackupKind.ENCRYPTED),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            BackupRouting.route(true, true, ServiceOperations.BackupKind.NONE),
        )
    }

    /**
     * A restore has ONE implementation on either route, so unlike backups there
     * is no per-flavour exception — vaultwarden included.
     */
    @Test
    fun `a restore routes on the agent alone`() {
        assertEquals(ServiceControlRoute.AGENT, RestoreRouting.route(true, true))
        assertEquals(ServiceControlRoute.SSH, RestoreRouting.route(false, true))
    }

    /**
     * **The full erase never routes to the agent.** It stops `gryonixnexusd` and
     * deletes its binary, so the stream reporting the erase is killed BY the
     * erase — leaving the client unable to tell "wiped as asked" from "the
     * agent died and I have no idea what state this machine is in".
     */
    @Test
    fun `removing everything stays on SSH, removing one service does not`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            ServiceRemovalRouting.route(RemovalScope.SERVICE, true, true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceRemovalRouting.route(RemovalScope.EVERYTHING, true, true),
        )
    }

    /** A deployment can have an agent and no mail engine — then there is nothing to route. */
    @Test
    fun `mail routing asks whether there is an engine at all`() {
        assertEquals(ServiceControlRoute.AGENT, MailboxRouting.route(true, true, hasEngine = true))
        assertEquals(ServiceControlRoute.SSH, MailboxRouting.route(true, true, hasEngine = false))
        assertEquals(
            ServiceControlRoute.AGENT,
            DKIMRouting.route(true, true, hasMailEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            DKIMRouting.route(true, true, hasMailEngine = false),
        )
    }

    @Test
    fun `the lockdown and update toggles add no condition of their own`() {
        assertEquals(ServiceControlRoute.AGENT, LockdownRouting.route(true, true))
        assertEquals(ServiceControlRoute.SSH, LockdownRouting.route(true, false))
        assertEquals(ServiceControlRoute.AGENT, ServiceUpdateRouting.route(true, true))
        assertEquals(ServiceControlRoute.SSH, ServiceUpdateRouting.route(false, true))
    }
}

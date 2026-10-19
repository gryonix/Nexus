package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownManaging
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The machine's own actions */
class HostActionsViewModelTests {
    private val vps = SSHHostID.VPS
    private val home = SSHHostID.HOME

    private fun single(services: Set<ServiceID> = emptySet()) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
    )

    private fun pair(
        services: Set<ServiceID> = emptySet(),
        additionalDomains: List<String> = emptyList(),
    ) = Deployment(
        id = "S-2",
        name = "pair",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        additionalDomains = additionalDomains,
        entry = HostEndpoint(host = "203.0.113.41", user = "root"),
        homeWGAddress = "10.8.0.2",
        services = services,
    )

    private class Recording(
        private val refuse: Set<SSHHostID> = emptySet(),
    ) : SSHCommandRunner {
        val ran = mutableListOf<Pair<String, SSHHostID>>()
        val detached = mutableListOf<Pair<String, SSHHostID>>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            ran += command to host
            if (host in refuse) return ExecResult(exitCode = 1, stdout = "", stderr = "no sudo")
            return ExecResult(exitCode = 0, stdout = "", stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
            emptyFlow()

        override suspend fun fireAndForget(command: String, host: SSHHostID) {
            detached += command to host
        }

        override suspend fun disconnect() = Unit
    }

    private class ScriptedGuard(
        private val answers: List<Result<AdminLockdownState>>,
    ) : AdminLockdownManaging {
        val asked = mutableListOf<String>()
        private var reads = 0

        private fun next(): AdminLockdownState {
            val answer = answers[minOf(reads, answers.size - 1)]
            reads += 1
            return answer.getOrThrow()
        }

        override suspend fun status(): AdminLockdownState {
            asked += "status"
            return next()
        }

        override suspend fun set(enabled: Boolean): AdminLockdownState {
            asked += if (enabled) "on" else "off"
            return next()
        }

        override suspend fun set(hosts: List<String>): AdminLockdownState {
            asked += "only ${hosts.joinToString(" ")}"
            return next()
        }
    }

    private object NoGuard : AdminLockdownManaging {
        override suspend fun status() = error("the guard must not be asked here")
        override suspend fun set(enabled: Boolean) = error("the guard must not be asked here")
        override suspend fun set(hosts: List<String>) = error("the guard must not be asked here")
    }

    // ------------------------------------------------------------ sshd

    @Test
    fun `restarting sshd walks every machine, the relay last`() = runTest {
        val runner = Recording()
        val server = pair()
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { runner },
            lockdowns = { NoGuard },
        )

        model.restartSSHD(server)
        runCurrent()

        assertEquals(
            listOf(CommandCatalog.RESTART_SSHD to home, CommandCatalog.RESTART_SSHD to vps),
            runner.ran,
        )
        val outcome = assertNotNull(model.state.value.outcome)
        assertEquals(HostAction.RESTART_SSHD, outcome.action)
        assertNull(outcome.errorMessage)
        assertNull(model.state.value.running)
    }

    @Test
    fun `a machine that refuses stops the walk and is named`() = runTest {
        val runner = Recording(refuse = setOf(home))
        val server = pair()
        var released = 0
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { runner },
            lockdowns = { NoGuard },
            release = { released += 1 },
        )

        model.restartSSHD(server)
        runCurrent()

        assertEquals(listOf(CommandCatalog.RESTART_SSHD to home), runner.ran)
        val outcome = assertNotNull(model.state.value.outcome)
        assertEquals(home, outcome.host)
        assertTrue(outcome.isError)
        assertEquals(1, released)
    }

    @Test
    fun `a single-host server restarts its one machine`() = runTest {
        val runner = Recording()
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { runner },
            lockdowns = { NoGuard },
        )

        model.restartSSHD(single())
        runCurrent()

        assertEquals(listOf(CommandCatalog.RESTART_SSHD to vps), runner.ran)
    }

    // ---------------------------------------------------------- reboot

    @Test
    fun `a reboot is sent without waiting for an exit status`() = runTest {
        val runner = Recording()
        var released = 0
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { runner },
            lockdowns = { NoGuard },
            release = { released += 1 },
        )

        model.reboot(pair(), home)
        runCurrent()

        assertEquals(listOf(CommandCatalog.REBOOT_HOST to home), runner.detached)
        assertTrue(runner.ran.isEmpty())
        assertEquals(1, released)
        val outcome = assertNotNull(model.state.value.outcome)
        assertEquals(home, outcome.host)
        assertNull(outcome.errorMessage)
    }

    @Test
    fun `a shutdown goes to the machine that runs the services`() = runTest {
        val runner = Recording()
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { runner },
            lockdowns = { NoGuard },
        )

        model.powerOff(pair())
        runCurrent()

        val target = pair().nodes.first { it.runsServices }.sshHost
        assertEquals(listOf(CommandCatalog.POWER_OFF_HOST to target), runner.ran.filter { it.first == CommandCatalog.POWER_OFF_HOST })
        assertEquals(HostAction.POWER_OFF, assertNotNull(model.state.value.outcome).action)
    }

    @Test
    fun `a second action while one is running is ignored`() = runTest {
        val runner = Recording()
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { runner },
            lockdowns = { NoGuard },
        )

        model.restartSSHD(pair())
        model.reboot(pair(), vps)
        runCurrent()

        assertTrue(runner.detached.isEmpty())
    }

    // -------------------------------------------------------- lockdown

    @Test
    fun `the guard is offered only where the VPN panel installed it`() {
        assertTrue(
            HostActionsViewModel.hasAdminLockdown(single(setOf(ServiceID.VPN_PANEL, ServiceID.NEXTCLOUD)))
        )
        assertTrue(!HostActionsViewModel.hasAdminLockdown(single(setOf(ServiceID.NEXTCLOUD))))
    }

    @Test
    fun `the pages are the installed services that have a site`() {
        val pages = HostActionsViewModel.lockdownPages(
            single(setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME, ServiceID.WIREGUARD_VPN))
        )
        val hosts = pages.map { it.host }
        assertTrue(hosts.contains("files.example.test"), "$hosts")
        assertTrue(hosts.contains("dns.example.test"), "$hosts")
        assertEquals(hosts.size, hosts.toSet().size)
        assertTrue(pages.none { it.id == ServiceID.WIREGUARD_VPN })
    }

    @Test
    fun `guarding the last unguarded page asks for everything, not a list`() {
        val server = single(setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME))
        val request = HostActionsViewModel.request(
            deployment = server,
            current = AdminLockdownState.Only(setOf("files.example.test")),
            host = "dns.example.test",
            guarded = true,
        )
        assertEquals(LockdownRequest.All, request)
    }

    @Test
    fun `an explicit list names the mirrored aliases too`() {
        val server = pair(
            services = setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME),
            additionalDomains = listOf("alias.test"),
        )
        val request = HostActionsViewModel.request(
            deployment = server,
            current = AdminLockdownState.Off,
            host = "files.example.test",
            guarded = true,
        )
        assertEquals(
            LockdownRequest.Only(listOf("files.alias.test", "files.example.test")),
            request,
        )
    }

    @Test
    fun `unguarding the last page asks for an empty list`() {
        val server = single(setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME))
        val request = HostActionsViewModel.request(
            deployment = server,
            current = AdminLockdownState.Only(setOf("files.example.test")),
            host = "files.example.test",
            guarded = false,
        )
        assertEquals(LockdownRequest.Only(emptyList()), request)
    }

    @Test
    fun `a page toggle before the machine has answered sends nothing`() = runTest {
        val guard = ScriptedGuard(listOf(Result.success(AdminLockdownState.Off)))
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { Recording() },
            lockdowns = { guard },
        )

        model.setLockdown(single(setOf(ServiceID.NEXTCLOUD)), "files.example.test", true)
        runCurrent()

        assertTrue(guard.asked.isEmpty())
    }

    @Test
    fun `a page toggle after a read sends the whole wanted list`() = runTest {
        val guard = ScriptedGuard(
            listOf(
                Result.success(AdminLockdownState.Only(setOf("files.example.test"))),
                Result.success(AdminLockdownState.All),
            )
        )
        val server = single(setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME))
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { Recording() },
            lockdowns = { guard },
        )

        model.refreshLockdown(server)
        runCurrent()
        model.setLockdown(server, "dns.example.test", true)
        runCurrent()

        assertEquals(listOf("status", "on"), guard.asked)
        assertEquals(AdminLockdownState.All, model.state.value.lockdown.value)
    }

    @Test
    fun `a refused read is a reason, not a state`() = runTest {
        val guard = ScriptedGuard(
            listOf(
                Result.failure(IllegalStateException("the wrapper is not installed")),
                Result.success(AdminLockdownState.Off),
            )
        )
        var released = 0
        val server = single(setOf(ServiceID.VPN_PANEL))
        val model = HostActionsViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            runners = { Recording() },
            lockdowns = { guard },
            release = { released += 1 },
        )

        model.refreshLockdown(server)
        runCurrent()

        val failed = model.state.value.lockdown
        assertTrue(failed is LockdownRead.Failed, "$failed")
        assertEquals("the wrapper is not installed", failed.message)
        assertNull(model.state.value.lockdown.value)
        assertEquals(1, released)

        model.refreshLockdown(server)
        runCurrent()
        assertEquals(AdminLockdownState.Off, model.state.value.lockdown.value)
    }

    @Test
    fun `the config the wrappers run under is the deployment's own`() {
        val server = pair()
        val config = server.dashboardConfig
        // sudo compares its whitelist verbatim, so the user here has to be the
        // one the setup scripts were generated for.
        assertEquals("root", config.sshUser)
        assertEquals("203.0.113.41", config.vpsHost)
        assertEquals("10.8.0.2", config.homeWGAddress)
        assertEquals(server.timeouts.restartSeconds, config.restartTimeoutSeconds)
    }
}

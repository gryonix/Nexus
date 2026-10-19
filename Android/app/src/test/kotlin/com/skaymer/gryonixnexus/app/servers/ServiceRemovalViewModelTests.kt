package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceRemovalManaging
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Taking one service off a server */
class ServiceRemovalViewModelTests {
    private fun server(
        usesAgent: Boolean = false,
        services: Set<ServiceID> = setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME),
    ) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
        usesAgent = usesAgent,
    )

    private fun service(id: ServiceID): ManagedService = ServiceRegistry.service(id)!!

    private class Scripted(
        val fail: Boolean = false,
        val chunks: List<String> = emptyList(),
    ) : ServiceRemovalManaging {
        var asked: Pair<ServiceID, PurgeOptions>? = null

        override suspend fun remove(
            service: ManagedService,
            purge: PurgeOptions,
            onChunk: (String) -> Unit,
        ): String {
            asked = service.id to purge
            chunks.forEach(onChunk)
            if (fail) throw IOException("the wrapper never finished")
            return chunks.joinToString("")
        }
    }

    private fun model(
        scope: CoroutineScope,
        machine: Scripted = Scripted(),
        saved: MutableList<Deployment> = mutableListOf(),
        refresh: suspend (Deployment) -> Unit = {},
        agentTransportAvailable: Boolean = true,
    ) = ServiceRemovalViewModel(
        scope = scope,
        removals = { _, _ -> machine },
        refreshHostSurface = refresh,
        persist = { saved += it },
        agentTransportAvailable = agentTransportAvailable,
    )

    // ----------------------------------------------------- What comes down

    @Test
    fun `the VPN stack comes down as one unit`() {
        val removed = ServiceRemovalViewModel.removedServices(service(ServiceID.WIREGUARD_VPN))
        assertTrue(ServiceID.VPN_PANEL in removed)
        assertTrue(ServiceID.VPN_PROTOCOLS.all { it in removed })
        assertTrue(ServiceRemovalViewModel.alsoRemovedNames(service(ServiceID.WIREGUARD_VPN)).isNotEmpty())
    }

    @Test
    fun `every other service is only itself`() {
        assertEquals(
            setOf(ServiceID.NEXTCLOUD),
            ServiceRemovalViewModel.removedServices(service(ServiceID.NEXTCLOUD)),
        )
        assertTrue(ServiceRemovalViewModel.alsoRemovedNames(service(ServiceID.NEXTCLOUD)).isEmpty())
    }

    // ------------------------------------------------- The panels left open

    @Test
    fun `removing the VPN names the panels that stop being VPN-only`() {
        val deployment = server(services = setOf(ServiceID.VPN_PANEL, ServiceID.ADGUARD_HOME))
        val pages = HostActionsViewModel.lockdownPages(deployment)
        val named = ServiceRemovalViewModel.unguardedPanelNames(
            service(ServiceID.WIREGUARD_VPN),
            AdminLockdownState.All,
            pages,
        )
        assertEquals(pages.filter { it.id != ServiceID.VPN_PANEL }.map { it.name }, named)
    }

    @Test
    fun `a guard that is already off warns about nothing`() {
        assertTrue(
            ServiceRemovalViewModel.unguardedPanelNames(
                service(ServiceID.WIREGUARD_VPN),
                AdminLockdownState.Off,
                HostActionsViewModel.lockdownPages(server()),
            ).isEmpty()
        )
        assertTrue(
            ServiceRemovalViewModel.unguardedPanelNames(
                service(ServiceID.WIREGUARD_VPN),
                null,
                HostActionsViewModel.lockdownPages(server()),
            ).isEmpty()
        )
    }

    @Test
    fun `removing something other than the VPN leaves the guard alone`() {
        assertTrue(
            ServiceRemovalViewModel.unguardedPanelNames(
                service(ServiceID.NEXTCLOUD),
                AdminLockdownState.All,
                HostActionsViewModel.lockdownPages(server()),
            ).isEmpty()
        )
    }

    // ------------------------------------------------------- What it says

    @Test
    fun `each pair of toggles has its own sentence`() {
        assertEquals(PurgeWarning.NOTHING, ServiceRemovalViewModel.warning(PurgeOptions.NONE))
        assertEquals(
            PurgeWarning.DATA,
            ServiceRemovalViewModel.warning(PurgeOptions(data = true, backups = false)),
        )
        assertEquals(
            PurgeWarning.BACKUPS,
            ServiceRemovalViewModel.warning(PurgeOptions(data = false, backups = true)),
        )
        assertEquals(
            PurgeWarning.EVERYTHING,
            ServiceRemovalViewModel.warning(PurgeOptions(data = true, backups = true)),
        )
    }

    // ----------------------------------------------------------- The record

    @Test
    fun `a removal that worked rewrites the stored server`() = runTest(StandardTestDispatcher()) {
        val saved = mutableListOf<Deployment>()
        val removal = model(this, saved = saved)
        removal.remove(server(), service(ServiceID.NEXTCLOUD), PurgeOptions.NONE)
        runCurrent()

        assertEquals(setOf(ServiceID.ADGUARD_HOME), saved.single().services)
        assertTrue(removal.state.value.run!!.succeeded)
    }

    @Test
    fun `a removal that failed leaves the service in the list`() = runTest(StandardTestDispatcher()) {
        val saved = mutableListOf<Deployment>()
        val removal = model(this, machine = Scripted(fail = true), saved = saved)
        removal.remove(server(), service(ServiceID.NEXTCLOUD), PurgeOptions.NONE)
        runCurrent()

        assertTrue(saved.isEmpty())
        val run = removal.state.value.run!!
        assertFalse(run.succeeded)
        assertEquals("the wrapper never finished", run.errorMessage)
    }

    @Test
    fun `removing one VPN protocol takes every one of them out of the record`() =
        runTest(StandardTestDispatcher()) {
            val saved = mutableListOf<Deployment>()
            val removal = model(
                this,
                saved = saved,
                machine = Scripted(),
            )
            val deployment = server(
                services = setOf(ServiceID.WIREGUARD_VPN, ServiceID.VPN_PANEL, ServiceID.NEXTCLOUD),
            )
            removal.remove(deployment, service(ServiceID.WIREGUARD_VPN), PurgeOptions.NONE)
            runCurrent()

            assertEquals(setOf(ServiceID.NEXTCLOUD), saved.single().services)
        }

    @Test
    fun `the purge the owner asked for travels to the machine`() = runTest(StandardTestDispatcher()) {
        val machine = Scripted()
        val removal = model(this, machine = machine)
        val purge = PurgeOptions(data = true, backups = true)
        removal.remove(server(), service(ServiceID.NEXTCLOUD), purge)
        runCurrent()

        assertEquals(ServiceID.NEXTCLOUD to purge, machine.asked)
        assertEquals(purge, removal.state.value.run!!.purge)
    }

    // --------------------------------------------------------- The wrappers

    @Test
    fun `an agent host is told the service list changed`() = runTest(StandardTestDispatcher()) {
        var refreshed = 0
        val removal = model(this, refresh = { refreshed += 1 })
        removal.remove(server(usesAgent = true), service(ServiceID.NEXTCLOUD), PurgeOptions.NONE)
        runCurrent()

        assertEquals(1, refreshed)
    }

    @Test
    fun `a server without an agent has no surface to redraw`() = runTest(StandardTestDispatcher()) {
        var refreshed = 0
        val removal = model(this, refresh = { refreshed += 1 })
        removal.remove(server(usesAgent = false), service(ServiceID.NEXTCLOUD), PurgeOptions.NONE)
        runCurrent()
        assertEquals(0, refreshed)
    }

    @Test
    fun `a surface that could not be redrawn is a note, not a failed removal`() =
        runTest(StandardTestDispatcher()) {
            val saved = mutableListOf<Deployment>()
            val removal = model(
                this,
                saved = saved,
                refresh = { throw IOException("the agent did not answer") },
            )
            removal.remove(server(usesAgent = true), service(ServiceID.NEXTCLOUD), PurgeOptions.NONE)
            runCurrent()

            val run = removal.state.value.run!!
            assertTrue(run.succeeded)
            assertNull(run.errorMessage)
            assertEquals("the agent did not answer", run.note)
            assertEquals(1, saved.size)
        }

    // --------------------------------------------------------- The routing

    @Test
    fun `one service may go through the agent, and the log is cleaned as it arrives`() =
        runTest(StandardTestDispatcher()) {
            assertEquals(ServiceControlRoute.AGENT, model(this).route(server(usesAgent = true)))
            assertEquals(ServiceControlRoute.SSH, model(this).route(server(usesAgent = false)))

            val removal = model(
                this,
                machine = Scripted(chunks = listOf("stopping\n", "GRYONIXNEXUS_UNINSTALL_DONE\n")),
            )
            removal.remove(server(), service(ServiceID.NEXTCLOUD), PurgeOptions.NONE)
            runCurrent()
            assertFalse(removal.state.value.run!!.log.contains("GRYONIXNEXUS_"))
        }

    @Test
    fun `removing one VPN protocol keeps the others and the panel`() {
        val installed = setOf(ServiceID.WIREGUARD_VPN, ServiceID.XRAY_REALITY, ServiceID.VPN_PANEL)
        val xray = service(ServiceID.XRAY_REALITY)
        assertEquals(setOf(ServiceID.WIREGUARD_VPN), ServiceRemovalViewModel.remainingVPNProtocols(xray, installed))
        assertEquals(setOf(ServiceID.XRAY_REALITY), ServiceRemovalViewModel.removedServices(xray, installed))
        assertTrue(ServiceRemovalViewModel.alsoRemovedNames(xray, installed).isEmpty())
        val last = setOf(ServiceID.XRAY_REALITY, ServiceID.VPN_PANEL)
        assertTrue(ServiceID.VPN_PANEL in ServiceRemovalViewModel.removedServices(xray, last))
    }
}

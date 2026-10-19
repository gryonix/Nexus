package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentcontrol.AgentInstallContext
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallSettings
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
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

/** Growing a server that already runs */
class AddServiceViewModelTests {
    private fun server(
        usesAgent: Boolean = true,
        services: Set<ServiceID> = setOf(ServiceID.NEXTCLOUD),
        scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
    ) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
        usesAgent = usesAgent,
        scope = scope,
    )

    private class Recorder {
        val asked = mutableListOf<Pair<ServiceID, AgentInstallContext>>()
        var failOn: ServiceID? = null
    }

    private fun model(
        scope: CoroutineScope,
        recorder: Recorder = Recorder(),
        saved: MutableList<Deployment> = mutableListOf(),
        onHost: Set<ServiceID> = emptySet(),
    ) = AddServiceViewModel(
        scope = scope,
        installs = { _, service, context, onChunk ->
            recorder.asked += service to context
            onChunk("installing $service\n")
            if (recorder.failOn == service) throw IOException("the agent refused")
        },
        contexts = { deployment, _ -> AgentInstallContext(domain = deployment.domain) },
        installedOnHost = { onHost },
        persist = { saved += it },
    )

    // ------------------------------------------------------- Who may offer

    @Test
    fun `every server can grow where the agent transport exists`() {
        assertTrue(AddServiceViewModel.canAdd(server(usesAgent = true)))
        assertTrue(AddServiceViewModel.canAdd(server(usesAgent = false)))
        assertFalse(
            AddServiceViewModel.canAdd(server(usesAgent = true), agentTransportAvailable = false)
        )
    }

    @Test
    fun `a server without the agent gets it before its services`() = runTest {
        val steps = mutableListOf<String>()
        val saved = mutableListOf<Deployment>()
        val model = AddServiceViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            installs = { deployment, service, _, _ -> steps += "service $service agent=${deployment.usesAgent}" },
            contexts = { deployment, _ -> AgentInstallContext(domain = deployment.domain) },
            installedOnHost = { emptySet() },
            persist = { saved += it },
            installAgent = { deployment, onChunk -> steps += "agent"; onChunk("agent up\n"); deployment },
        )
        model.install(server(usesAgent = false), listOf(ServiceRegistry.service(ServiceID.JELLYFIN)!!))
        runCurrent()
        assertEquals(listOf("agent", "service ${ServiceID.JELLYFIN} agent=true"), steps)
        assertTrue(saved.first().usesAgent)
        assertTrue(model.state.value.run!!.isFinished)
        assertNull(model.state.value.run!!.errorMessage)
    }

    @Test
    fun `a failed agent install stops before any service`() = runTest {
        val asked = mutableListOf<ServiceID>()
        val model = AddServiceViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            installs = { _, service, _, _ -> asked += service },
            contexts = { deployment, _ -> AgentInstallContext(domain = deployment.domain) },
            installAgent = { _, _ -> throw IOException("sudo needs a password") },
        )
        model.install(server(usesAgent = false), listOf(ServiceRegistry.service(ServiceID.JELLYFIN)!!))
        runCurrent()
        assertTrue(asked.isEmpty())
        assertEquals("sudo needs a password", model.state.value.run!!.errorMessage)
    }

    @Test
    fun `the tunnel reaches the agent with its connector token`() = runTest {
        val recorder = Recorder()
        val model = AddServiceViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            installs = { _, service, context, _ -> recorder.asked += service to context },
            contexts = { deployment, _ -> AgentInstallContext(domain = deployment.domain) },
            beforeInstall = { _, service ->
                if (service.id == ServiceID.CLOUDFLARED) mapOf(AgentInstallSettings.CLOUDFLARED_TOKEN_KEY to "eyJ") else emptyMap()
            },
        )
        model.install(
            server(scope = DeploymentScope.CLOUDFLARE_TUNNEL),
            listOf(ServiceRegistry.service(ServiceID.CLOUDFLARED)!!, ServiceRegistry.service(ServiceID.JELLYFIN)!!),
        )
        runCurrent()
        val tokens = recorder.asked.associate { (id, context) ->
            id to context.settings[AgentInstallSettings.CLOUDFLARED_TOKEN_KEY]
        }
        assertEquals("eyJ", tokens[ServiceID.CLOUDFLARED])
        assertNull(tokens[ServiceID.JELLYFIN])
    }

    // ---------------------------------------------------- What is offered

    @Test
    fun `what is installed is not offered again`() {
        val offered = AddServiceViewModel.available(setOf(ServiceID.NEXTCLOUD), localOnly = false)
            .flatMap { it.second }
            .map { it.id }
        assertFalse(ServiceID.NEXTCLOUD in offered)
    }

    @Test
    fun `a shelf-mate of something installed is not offered`() {
        val offered = AddServiceViewModel.available(setOf(ServiceID.MAILCOW), localOnly = false)
            .flatMap { it.second }
            .map { it.id }
        assertFalse(ServiceID.MAILU in offered)
        assertFalse(ServiceID.DOCKER_MAILSERVER in offered)
    }

    @Test
    fun `the panel is never picked on its own`() {
        // It arrives WITH a protocol; installed alone it advertises nothing.
        val offered = AddServiceViewModel.available(emptySet(), localOnly = false)
            .flatMap { it.second }
        assertTrue(offered.none { it.category == ServiceCategory.IMPLICIT })
        assertTrue(offered.none { it.id == ServiceID.VPN_PANEL })
    }

    @Test
    fun `a local-only server is offered neither mail nor a VPN`() {
        val offered = AddServiceViewModel.available(emptySet(), localOnly = true).map { it.first }
        assertFalse(ServiceCategory.MAIL in offered)
        assertFalse(ServiceCategory.VPN in offered)
        assertTrue(offered.isNotEmpty())
    }

    @Test
    fun `the connector is not offered while no token can be issued`() {
        val offered = AddServiceViewModel.available(emptySet(), localOnly = false)
            .flatMap { it.second }.map { it.id }
        assertFalse(ServiceID.CLOUDFLARED in offered)
        val withToken = AddServiceViewModel.available(
            emptySet(), localOnly = false, canIssueTunnelToken = true,
        ).flatMap { it.second }.map { it.id }
        assertTrue(ServiceID.CLOUDFLARED in withToken)
    }

    // ------------------------------------------------------- What is picked

    @Test
    fun `picking inside an exclusive shelf replaces rather than accumulates`() {
        val mailcow = ServiceRegistry.service(ServiceID.MAILCOW)!!
        val mailu = ServiceRegistry.service(ServiceID.MAILU)!!
        val picked = AddServiceViewModel.toggle(
            AddServiceViewModel.toggle(emptySet(), mailcow),
            mailu,
        )
        assertEquals(setOf(ServiceID.MAILU), picked)
    }

    @Test
    fun `picking twice unpicks, and picks elsewhere accumulate`() {
        val nextcloud = ServiceRegistry.service(ServiceID.NEXTCLOUD)!!
        val adguard = ServiceRegistry.service(ServiceID.ADGUARD_HOME)!!
        var picked = AddServiceViewModel.toggle(emptySet(), nextcloud)
        picked = AddServiceViewModel.toggle(picked, adguard)
        assertEquals(setOf(ServiceID.NEXTCLOUD, ServiceID.ADGUARD_HOME), picked)
        picked = AddServiceViewModel.toggle(picked, nextcloud)
        assertEquals(setOf(ServiceID.ADGUARD_HOME), picked)
    }

    @Test
    fun `the chosen are installed in catalog order`() {
        val order = AddServiceViewModel.chosen(setOf(ServiceID.ADGUARD_HOME, ServiceID.NEXTCLOUD))
            .map { it.id }
        val catalog = ServiceRegistry.all.map { it.id }
        assertEquals(order.sortedBy { catalog.indexOf(it) }, order)
    }

    // ------------------------------------------------------------- The run

    @Test
    fun `each service that lands is written before the next starts`() =
        runTest(StandardTestDispatcher()) {
            val recorder = Recorder().apply { failOn = ServiceID.ADGUARD_HOME }
            val saved = mutableListOf<Deployment>()
            val adding = model(this, recorder, saved)
            adding.install(
                server(services = emptySet()),
                listOf(
                    ServiceRegistry.service(ServiceID.NEXTCLOUD)!!,
                    ServiceRegistry.service(ServiceID.ADGUARD_HOME)!!,
                ),
            )
            runCurrent()

            assertEquals(listOf(setOf(ServiceID.NEXTCLOUD)), saved.map { it.services })
            val run = adding.state.value.run!!
            assertEquals(listOf(ServiceID.NEXTCLOUD), run.installed)
            assertEquals("the agent refused", run.errorMessage)
            assertNull(run.current)
        }

    @Test
    fun `a VPN protocol brings the panel into the record with it`() =
        runTest(StandardTestDispatcher()) {
            val saved = mutableListOf<Deployment>()
            val adding = model(this, saved = saved)
            adding.install(
                server(services = emptySet()),
                listOf(ServiceRegistry.service(ServiceID.WIREGUARD_VPN)!!),
            )
            runCurrent()

            assertEquals(
                setOf(ServiceID.WIREGUARD_VPN, ServiceID.VPN_PANEL),
                saved.single().services,
            )
        }

    @Test
    fun `the protocol list sent is what the HOST will run afterwards`() =
        runTest(StandardTestDispatcher()) {
            val recorder = Recorder()
            val adding = model(this, recorder, onHost = setOf(ServiceID.OPEN_VPN))
            adding.install(
                server(services = emptySet()),
                listOf(ServiceRegistry.service(ServiceID.WIREGUARD_VPN)!!),
            )
            runCurrent()

            val sent = recorder.asked.single().second.settings[AgentInstallSettings.VPN_PROTOCOLS_KEY]
            assertTrue(sent!!.contains(ServiceID.OPEN_VPN.rawValue))
            assertTrue(sent.contains(ServiceID.WIREGUARD_VPN.rawValue))
        }

    @Test
    fun `a service that is not a VPN sends no protocol list at all`() =
        runTest(StandardTestDispatcher()) {
            val recorder = Recorder()
            val adding = model(this, recorder)
            adding.install(
                server(services = emptySet()),
                listOf(ServiceRegistry.service(ServiceID.NEXTCLOUD)!!),
            )
            runCurrent()
            assertNull(recorder.asked.single().second.settings[AgentInstallSettings.VPN_PROTOCOLS_KEY])
        }

    @Test
    fun `the whole list goes to the agent as one plan and what it installed is recorded`() = runTest {
        val sent = mutableListOf<List<ServiceID>>()
        val saved = mutableListOf<Deployment>()
        val model = AddServiceViewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            installs = { _, _, _, _ -> error("one by one is not used when the agent takes a plan") },
            contexts = { deployment, _ -> AgentInstallContext(domain = deployment.domain) },
            persist = { saved += it },
            plans = { _, requests, _, _, _ ->
                sent += requests.map { it.first }
                setOf(ServiceID.JELLYFIN)
            },
        )
        val chosen = listOf(ServiceID.JELLYFIN, ServiceID.IMMICH).map { ServiceRegistry.service(it)!! }
        model.install(server(), chosen)
        testScheduler.advanceUntilIdle()

        assertEquals(listOf(listOf(ServiceID.JELLYFIN, ServiceID.IMMICH)), sent)
        assertTrue(ServiceID.JELLYFIN in saved.last().services)
        assertFalse(ServiceID.IMMICH in saved.last().services)
        assertTrue(model.state.value.run!!.errorMessage != null, "a service the plan left out is reported")
    }

    @Test
    fun `a new Reality key is asked for once, then this phone is refreshed`() = runTest {
        val recorder = Recorder()
        var refreshed = false
        val model = model(CoroutineScope(StandardTestDispatcher(testScheduler)), recorder)
        val vless = server(services = setOf(ServiceID.XRAY_REALITY))
        model.renewRealityKey(vless) { refreshed = true }
        runCurrent()
        val (service, context) = recorder.asked.single()
        assertEquals(ServiceID.XRAY_REALITY, service)
        assertTrue(context.settings[AgentInstallSettings.XRAY_REALITY_NEW_KEY_KEY].orEmpty().isNotBlank())
        assertTrue(refreshed)
        model.reapply(vless, ServiceRegistry.service(ServiceID.XRAY_REALITY)!!)
        runCurrent()
        assertNull(recorder.asked.last().second.settings[AgentInstallSettings.XRAY_REALITY_NEW_KEY_KEY], "only once")
    }
}

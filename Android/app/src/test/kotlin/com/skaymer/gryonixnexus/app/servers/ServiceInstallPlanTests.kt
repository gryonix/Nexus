package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ServiceInstallPlanTests {
    private fun services(ids: List<ServiceID>) = ids.mapNotNull { ServiceRegistry.service(it) }

    @Test
    fun `new VPN protocols go to the server together`() {
        val steps = ServiceInstallPlan.steps(
            services(listOf(ServiceID.AMNEZIA_WG, ServiceID.VAULTWARDEN, ServiceID.XRAY_REALITY)), emptySet(),
        )
        assertEquals(listOf(ServiceID.AMNEZIA_WG, ServiceID.VAULTWARDEN), steps.map { it.service.id })
        assertEquals(setOf(ServiceID.XRAY_REALITY), steps.first().alsoProtocols)
    }

    @Test
    fun `only what is not installed is planned`() {
        val steps = ServiceInstallPlan.steps(
            services(listOf(ServiceID.AMNEZIA_WG, ServiceID.XRAY_REALITY)), setOf(ServiceID.AMNEZIA_WG),
        )
        assertEquals(listOf(ServiceID.XRAY_REALITY), steps.map { it.service.id })
    }

    @Test
    fun `setup sends the VPN once and skips what the host runs`() {
        val chosen = services(listOf(ServiceID.VPN_PANEL, ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG, ServiceID.VAULTWARDEN))
        val run = ServiceInstallPlan.agentRun(chosen, setOf(ServiceID.WIREGUARD_VPN, ServiceID.VAULTWARDEN))
        assertEquals(listOf(ServiceID.WIREGUARD_VPN), run.map { it.id })
        assertTrue(ServiceInstallPlan.agentRun(chosen.take(3), setOf(ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG)).isEmpty())
    }

    @Test
    fun `a repair runs every service again but leaves the tunnel`() {
        val steps = ServiceInstallPlan.rerun(
            services(listOf(ServiceID.NEXTCLOUD, ServiceID.VPN_PANEL, ServiceID.AMNEZIA_WG, ServiceID.XRAY_REALITY, ServiceID.CLOUDFLARED)),
        )
        assertEquals(listOf(ServiceID.NEXTCLOUD, ServiceID.AMNEZIA_WG), steps.map { it.service.id })
    }
}

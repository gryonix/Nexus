package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The web addresses of what a server runs */
class WebSitesTests {
    private fun server(domain: String, services: Set<ServiceID>) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = domain,
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
    )

    @Test
    fun `a service with a web UI gets the address the catalog gave its site`() {
        val deployment = server("example.test", setOf(ServiceID.NEXTCLOUD))
        val site = WebSites.of(deployment.services, deployment.serviceContext).single()
        assertEquals(ServiceID.NEXTCLOUD, site.id)
        assertTrue(site.host.endsWith(".example.test"))
        assertEquals("https://${site.host}", site.url)
    }

    @Test
    fun `a server with no domain gets no rows at all`() {
        val deployment = server("", setOf(ServiceID.NEXTCLOUD))
        assertTrue(WebSites.of(deployment.services, deployment.serviceContext).isEmpty())
        assertTrue(WebSites.needDomain(deployment.services, deployment.serviceContext))
    }

    @Test
    fun `a VPN-only server has no sites and is missing no domain either`() {
        val deployment = server("example.test", setOf(ServiceID.WIREGUARD_VPN))
        assertTrue(WebSites.of(deployment.services, deployment.serviceContext).isEmpty())
        assertFalse(WebSites.needDomain(deployment.services, deployment.serviceContext))
    }
}

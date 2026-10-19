package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

/** What a service row says its address is */
class ServiceAddressTests {
    private fun server(domain: String) = Deployment(
        id = "A-1",
        name = "one",
        topology = Topology.SINGLE_HOST,
        domain = domain,
        entry = HostEndpoint(host = "203.0.113.50", user = "root"),
        services = setOf(ServiceID.ADGUARD_HOME),
    )

    private val adguard = ServiceRegistry.service(ServiceID.ADGUARD_HOME)!!

    @Test
    fun `a domain gives the catalog's own name`() {
        assertEquals("dns.example.test", ServiceAddress.of(adguard, server("example.test").serviceContext))
    }

    /** Without one, it says nothing — both halves asserted, because a rule
     * that answered null for everything would pass the second alone. */
    @Test
    fun `no domain gives no address`() {
        assertNull(ServiceAddress.of(adguard, server("").serviceContext))
    }
}

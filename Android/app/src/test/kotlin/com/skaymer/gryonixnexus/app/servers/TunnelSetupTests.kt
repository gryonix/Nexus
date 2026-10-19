package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class TunnelSetupTests {
    private val server = Deployment(
        id = "T-1",
        name = "tunnel",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        additionalDomains = listOf("example.org"),
        entry = HostEndpoint(host = "192.168.1.20", user = "root"),
        services = setOf(ServiceID.CLOUDFLARED, ServiceID.VAULTWARDEN, ServiceID.JELLYFIN),
        scope = DeploymentScope.CLOUDFLARE_TUNNEL,
    )

    @Test
    fun `the tunnel is named after the domain`() {
        assertEquals("gryonixnexus-example-test", TunnelSetup.name(server))
    }

    @Test
    fun `every web name is routed, mirrored domains included, the connector itself not`() {
        val names = TunnelSetup.webNames(server)
        assertEquals(names.distinct(), names)
        assertEquals(4, names.size, names.toString())
        assertEquals(2, names.count { it.endsWith(".example.org") }, names.toString())
    }

    @Test
    fun `the mail host keeps its own records`() {
        val withMail = server.copy(services = server.services + ServiceID.MAILCOW)
        val names = TunnelSetup.webNames(withMail)
        assertEquals(emptyList(), names.filter { it.startsWith("mail.") }, names.toString())
        assertEquals(TunnelSetup.webNames(server), names)
    }

    @Test
    fun `without a tunnel token the install asks for one`() = runTest {
        val setup = TunnelSetup({ null }, { "dns" }, "needs a tunnel token", { "$it" })
        val failure = assertFailsWith<IllegalStateException> { setup.connectorToken(server) }
        assertEquals("needs a tunnel token", failure.message)
    }
}

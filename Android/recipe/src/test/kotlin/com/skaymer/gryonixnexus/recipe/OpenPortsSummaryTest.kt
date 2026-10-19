package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.core.Domain
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerNode
import com.skaymer.gryonixnexus.core.ServerRole
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class OpenPortsSummaryTest {
    private fun inputA(services: Set<ServiceID>) = MailRecipeInput(
        domain = Domain.of("example.com"),
        hostname = "mail.example.com",
        topology = Topology.SINGLE_HOST,
        servers = listOf(ServerNode(
            role = ServerRole.SINGLE_HOST,
            publicAddress = NetworkAddress.parse("203.0.113.10"),
            distribution = DistributionProfileID.DEBIAN
        )),
        services = services
    )

    private fun port(list: List<OpenPortRequirement>, port: Int,
                     proto: OpenPortRequirement.Proto): OpenPortRequirement? =
        list.firstOrNull { it.port == port && it.proto == proto }

    @Test
    fun `the summary follows the service selection`() {
        val vpnOnly = OpenPortsSummary.entryHostPorts(inputA(setOf(ServiceID.WIREGUARD_VPN)))
        assertNotNull(port(vpnOnly, 22, OpenPortRequirement.Proto.TCP))
        assertNotNull(port(vpnOnly, 443, OpenPortRequirement.Proto.TCP),
                      "the VPN panel rides behind Caddy")
        assertNotNull(port(vpnOnly, 51820, OpenPortRequirement.Proto.UDP))
        assertNull(port(vpnOnly, 25, OpenPortRequirement.Proto.TCP), "no mail selected — no SMTP")

        val withMailcow = OpenPortsSummary.entryHostPorts(inputA(setOf(ServiceID.MAILCOW)))
        assertEquals("Mailcow (SMTP)", port(withMailcow, 25, OpenPortRequirement.Proto.TCP)?.purpose)
        assertNotNull(port(withMailcow, 4190, OpenPortRequirement.Proto.TCP),
                      "Sieve comes with mailcow")
        assertNull(port(withMailcow, 51820, OpenPortRequirement.Proto.UDP),
                   "no VPN, no tunnel in scenario A")
    }

    @Test
    fun `scenario B opens the tunnel port and scenario A does not`() {
        val relay = OpenPortsSummary.entryHostPorts(MailRecipeInput(
            domain = Domain.of("example.com"),
            hostname = "mail.example.com",
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            servers = listOf(
                ServerNode(role = ServerRole.VPS_RELAY,
                           publicAddress = NetworkAddress.parse("203.0.113.10"),
                           vpnAddress = NetworkAddress.parse("10.8.0.1"),
                           distribution = DistributionProfileID.DEBIAN),
                ServerNode(role = ServerRole.HOME_BACKEND,
                           vpnAddress = NetworkAddress.parse("10.8.0.2"),
                           distribution = DistributionProfileID.UBUNTU)
            ),
            services = emptySet()
        ))
        assertEquals("WireGuard (VPS ↔ home)",
                     port(relay, 51820, OpenPortRequirement.Proto.UDP)?.purpose)
        assertNull(port(OpenPortsSummary.entryHostPorts(inputA(emptySet())),
                        51820, OpenPortRequirement.Proto.UDP))
    }

    @Test
    fun `the rows come out in port order`() {
        val ports = OpenPortsSummary.entryHostPorts(inputA(setOf(ServiceID.MAILCOW))).map { it.port }
        assertEquals(ports.sorted(), ports)
    }
}

package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Adopting a machine that already runs the agent */
class AgentAdoptionTests {
    @Test
    fun `a refused key is not a statement about the agent`() {
        val refused = AgentAdoption.failure(
            IllegalStateException("Exhausted available authentication methods"),
        )
        assertTrue(refused is AgentAdoption.Failure.KeyRefused, "got $refused")
        val dead = AgentAdoption.failure(java.net.ConnectException("Connection refused"))
        assertTrue(dead is AgentAdoption.Failure.Unreachable, "got $dead")
        assertEquals("Connection refused", dead.detail)
    }

    @Test
    fun `the protocols come from the containers, never from the id alone`() {
        val openvpn = AgentAdoption.services(listOf("vpn" to listOf("vpnpanel", "openvpn")))
        assertTrue(ServiceID.OPEN_VPN in openvpn)
        assertTrue(ServiceID.WIREGUARD_VPN !in openvpn)

        val plain = AgentAdoption.services(listOf("vpn" to listOf("vpnpanel")))
        assertTrue(ServiceID.WIREGUARD_VPN in plain)

        // And an ordinary service still arrives by its id.
        assertEquals(
            setOf(ServiceID.NEXTCLOUD),
            AgentAdoption.services(listOf("nextcloud" to listOf("nextcloud-app"))),
        )
    }

    @Test
    fun `the server is saved under the name it calls itself`() {
        assertEquals("relay", AgentAdoption.name("relay", fallback = "203.0.113.1"))
        assertEquals("203.0.113.1", AgentAdoption.name("  ", fallback = "203.0.113.1"))
    }

    @Test
    fun `no domain is a real answer and nothing is derived from a name`() {
        assertEquals("", AgentAdoption.domain(emptyList()))
        assertEquals("example.test", AgentAdoption.domain(listOf("example.test", "other.test")))
    }

    @Test
    fun `the pairing code is the token, not the line it is printed on`() {
        assertEquals(
            "ABCD-EFGH",
            com.skaymer.gryonixnexus.agentclient.PairingCode.parse(
                "Pairing code (valid 10 minutes): ABCD-EFGH\n",
            ),
        )
    }
}

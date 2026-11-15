package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class HomeUserTest {
    private fun relay(homeUser: String?) = Deployment(
        id = "A", name = "R", topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        entry = HostEndpoint("203.0.113.10", user = "server-user"),
        homeWGAddress = "10.8.0.2", homeUser = homeUser,
    )

    @Test
    fun homeNodeUsesItsOwnUserAndRoundTrips() {
        val text = DeploymentListCodec.encode(listOf(relay("root")))
        val decoded = DeploymentListCodec.decode(text).single()
        assertEquals("root", decoded.homeUser)
        assertEquals("root", decoded.nodes[1].endpoint.user)
        assertEquals("server-user", decoded.nodes[0].endpoint.user)
    }

    @Test
    fun nilHomeUserIsOmittedAndFallsBack() {
        val deployment = relay(null)
        assertFalse(DeploymentListCodec.encode(listOf(deployment)).contains("homeUser"))
        assertEquals("server-user", deployment.nodes[1].endpoint.user)
    }
}

package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test

/** Which machine's collector the history explorer reads */
class HistoryHostTest {
    private fun relayPair() = Deployment(
        id = "00000000-0000-0000-0000-0000000000B2",
        name = "b5.example.net",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "b5.example.net",
        entry = HostEndpoint(host = "203.0.113.20", user = "server-user"),
        homeWGAddress = "10.8.0.2",
    )

    @Test
    fun `the machine that was asked for is the machine that is read`() {
        val pair = relayPair()
        for (node in pair.nodes) {
            assertEquals(
                node.sshHost, HistoryHost.resolve(pair, node.sshHost),
                "the explorer must read the machine it was opened for",
            )
        }
    }

    /** The fallback is the services machine, not the first one */
    @Test
    fun `with nothing asked for it reads the machine that runs the services`() {
        val pair = relayPair()
        assertEquals(pair.servicesHost, HistoryHost.resolve(pair, null))
        assertNotEquals(
            pair.nodes.first().sshHost, HistoryHost.resolve(pair, null),
            "on a relay pair the first machine is the RELAY, which runs nothing",
        )
    }

    @Test
    fun `a machine this deployment no longer has is not read`() {
        val pair = relayPair()
        val gone = SSHHostID.node("00000000-0000-0000-0000-00000000DEAD")
        assertEquals(pair.servicesHost, HistoryHost.resolve(pair, gone))
    }
}

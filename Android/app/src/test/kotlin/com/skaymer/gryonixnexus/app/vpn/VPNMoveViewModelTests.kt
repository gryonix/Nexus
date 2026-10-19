package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.vpnRunsOnRelay
import gryonixnexusd.v1.VpnState
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okio.ByteString.Companion.encodeUtf8
import org.junit.jupiter.api.Test

/** Moving the VPN between home and the relay */
class VPNMoveViewModelTests {
    private fun pair(vpnOnRelay: Boolean? = null) = Deployment(
        id = "22222222-2222-2222-2222-222222222222",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.10", user = "admin"),
        homeWGAddress = "10.8.0.2",
        services = setOf(ServiceID.WIREGUARD_VPN, ServiceID.SHADOWSOCKS, ServiceID.VPN_PANEL),
        usesAgent = true,
        vpnOnRelay = vpnOnRelay,
    )

    private class Machine(val host: SSHHostID, val calls: MutableList<String>) : VPNMoveMachine {
        override suspend fun pack(directories: List<String>): VpnState {
            calls += "pack $host"
            return VpnState(archive = "tar".encodeUtf8(), directories = directories)
        }

        override suspend fun unpack(state: VpnState, replace: Boolean) {
            calls += "unpack $host replace=$replace"
        }

        override suspend fun removeVPN() {
            calls += "remove $host"
        }
    }

    private class Run(val installFails: Boolean = false) {
        val calls = mutableListOf<String>()
        val saved = mutableListOf<Deployment>()

        fun model(scope: CoroutineScope) = VPNMoveViewModel(
            scope = scope,
            machine = { _, host -> Machine(host, calls) },
            installVPN = { deployment ->
                calls += "install on ${deployment.vpnRunsOnRelay}"
                if (installFails) error("no docker")
            },
            reprovisionRelay = { calls += "relay"; listOf("relay ready") },
            persist = { saved += it },
        )
    }

    @Test
    fun `moving to the relay packs at home, unpacks there and retires the old copy without a second relay update`() = runTest {
        val run = Run()
        val moved = run.model(this).carry(pair(), toRelay = true)

        assertTrue(moved.vpnRunsOnRelay)
        assertEquals(
            listOf(
                "pack ${SSHHostID.HOME}", "unpack ${SSHHostID.VPS} replace=true",
                "install on true", "remove ${SSHHostID.HOME}",
            ),
            run.calls,
        )
        assertEquals(listOf(moved), run.saved)
    }

    @Test
    fun `moving replaces what the other machine still holds`() = runTest {
        val run = Run()
        val moved = run.model(this).carry(pair(vpnOnRelay = true), toRelay = false)

        assertNull(moved.vpnOnRelay)
        assertEquals("unpack ${SSHHostID.HOME} replace=true", run.calls[1])
        assertEquals(listOf("remove ${SSHHostID.VPS}", "relay"), run.calls.takeLast(2))
    }

    @Test
    fun `a failed install keeps the VPN where it was and clears the relay`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val run = Run(installFails = true)
        val model = run.model(CoroutineScope(dispatcher))

        model.move(pair(), toRelay = true)
        runCurrent()

        assertTrue(run.saved.isEmpty(), "the flag must not be saved")
        assertFalse(run.calls.contains("remove ${SSHHostID.HOME}"), "the old copy must keep running")
        assertEquals(listOf("remove ${SSHHostID.VPS}", "relay"), run.calls.takeLast(2))
        assertEquals("no docker", model.state.value.errorMessage)
        assertFalse(model.state.value.isRunning)
    }

    @Test
    fun `a failed move home clears home and leaves the relay alone`() = runTest {
        val run = Run(installFails = true)

        runCatching { run.model(this).carry(pair(vpnOnRelay = true), toRelay = false) }

        assertEquals(
            listOf(
                "pack ${SSHHostID.VPS}", "unpack ${SSHHostID.HOME} replace=true",
                "install on false", "remove ${SSHHostID.HOME}",
            ),
            run.calls,
        )
        assertTrue(run.saved.isEmpty())
    }

    @Test
    fun `the move is offered only with a relay and a VPN`() {
        assertTrue(VPNMoveViewModel.offers(pair()))
        assertFalse(VPNMoveViewModel.offers(pair().copy(services = setOf(ServiceID.NEXTCLOUD))))
        assertFalse(VPNMoveViewModel.offers(pair().copy(usesAgent = false)))
        assertFalse(VPNMoveViewModel.offers(pair().copy(topology = Topology.SINGLE_HOST)))
    }
}

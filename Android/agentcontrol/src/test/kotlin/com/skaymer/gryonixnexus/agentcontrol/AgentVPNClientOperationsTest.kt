package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.ListVpnClientsRequest
import gryonixnexusd.v1.VpnClient
import gryonixnexusd.v1.VpnClientConfig
import gryonixnexusd.v1.VpnClientList
import gryonixnexusd.v1.ImportVpnStateRequest
import gryonixnexusd.v1.ImportVpnStateResponse
import gryonixnexusd.v1.VpnDnsPriority
import gryonixnexusd.v1.VpnState
import okio.ByteString.Companion.encodeUtf8
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AgentVPNClientOperationsTest {
    private fun clients(vararg rows: Triple<String, String, String>) = VpnClientList(
        clients = rows.map { (id, name, detail) -> VpnClient(id = id, name = name, detail = detail) },
    )

    private fun ops(transport: FakeAgentTransport) = AgentVPNClientOperations(AgentClient(transport))

    // -------------------------------------------------- Listing and mapping

    @Test
    fun `the protocol travels as its catalog id and the rows are mapped`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Vpn/ListVpnClients",
            clients(
                Triple("1", "phone", "10.9.0.2"),
                Triple("2", "laptop", "10.9.0.3"),
            ),
        )

        val devices = ops(transport).list(ServiceID.AMNEZIA_WG)

        assertEquals(listOf("/gryonixnexusd.v1.Vpn/ListVpnClients"), transport.paths)
        assertEquals(
            ServiceID.AMNEZIA_WG.rawValue,
            ListVpnClientsRequest.ADAPTER.decode(transport.calls.first().second).protocol,
        )
        assertEquals(listOf("phone", "laptop"), devices.map { it.name })
        assertEquals(listOf("10.9.0.2", "10.9.0.3"), devices.map { it.detail })
    }

    @Test
    fun `adding answers with the listing the server returned`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Vpn/AddVpnClient", clients(Triple("1", "my_laptop", "certificate")))

        val devices = ops(transport).add(ServiceID.OPEN_VPN, named = "my laptop")

        assertEquals(listOf("/gryonixnexusd.v1.Vpn/AddVpnClient"), transport.paths)
        assertEquals(listOf("my_laptop"), devices.map { it.name }, "the panel's own name must win")
    }

    @Test
    fun `the server decides whether a QR code is worth drawing`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Vpn/GetVpnClientConfig",
            VpnClientConfig(text = "client\ndev tun\n", filename = "laptop.ovpn", qr_is_useful = false),
        )

        val configuration = ops(transport).configuration(ServiceID.OPEN_VPN, clientID = "1")

        assertEquals(listOf("/gryonixnexusd.v1.Vpn/GetVpnClientConfig"), transport.paths)
        assertFalse(configuration.qrIsUseful)
        assertEquals("laptop.ovpn", configuration.fileName)
        assertTrue(configuration.text.startsWith("client"))
    }

    @Test
    fun `the DNS order is read and written as the agent keeps it`() = runTest {
        val transport = FakeAgentTransport()
        val answer = VpnDnsPriority(resolvers = listOf("local", "9.9.9.9"), local_available = true, reachable = listOf(false, true))
        transport.reply("Vpn/GetVpnDnsPriority", answer)
        transport.reply("Vpn/SetVpnDnsPriority", answer)

        val read = ops(transport).dnsPriority()
        ops(transport).setDNSPriority(listOf("local", "9.9.9.9"))

        assertEquals(listOf("local", "9.9.9.9"), read.resolvers)
        assertTrue(read.localAvailable)
        assertFalse(read.isReachable(0))
        assertTrue(read.isReachable(5), "an unknown position counts as answering")
        assertEquals(
            listOf("local", "9.9.9.9"),
            VpnDnsPriority.ADAPTER.decode(transport.calls.last().second).resolvers,
        )
    }

    @Test
    fun `the VPN state travels whole between machines`() = runTest {
        val transport = FakeAgentTransport()
        val state = VpnState(archive = "tar".encodeUtf8(), directories = listOf("/opt/gryonix-vpn-panel"))
        transport.reply("Vpn/ExportVpnState", state)
        transport.reply("Vpn/ImportVpnState", ImportVpnStateResponse(directories = state.directories))
        val operations = ops(transport)

        val packed = operations.exportState(listOf("/opt/gryonix-vpn-panel", "/opt/missing"))
        val unpacked = operations.importState(packed, replace = true)

        assertEquals(state.directories, unpacked)

        val sent = ImportVpnStateRequest.ADAPTER.decode(transport.calls.last().second)
        assertEquals(state.archive, sent.archive)
        assertEquals(state.directories, sent.directories)
        assertTrue(sent.replace)
    }

    // ----------------------------------------------------------- The gate

    @Test
    fun `concurrent calls are serialized by a provided gate`() = runBlocking {
        val transport = GatedTransport(VpnClientList())
        val ops = AgentVPNClientOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6).map { launch(Dispatchers.Default) { ops.list(ServiceID.WIREGUARD_VPN) } }
            .forEach { it.join() }

        assertEquals(1, transport.highest, "more than one call ran at once under a limit-1 gate")
    }

    @Test
    fun `with no gate calls genuinely overlap`() = runBlocking {
        val transport = GatedTransport(VpnClientList())
        val ops = AgentVPNClientOperations(AgentClient(transport))

        (0 until 6).map { launch(Dispatchers.Default) { ops.list(ServiceID.WIREGUARD_VPN) } }
            .forEach { it.join() }

        assertTrue(
            transport.highest > 1,
            "calls did not overlap even without a gate — the harness is not sensitive",
        )
    }

    @Test
    fun `fetching a configuration goes through the gate too`() = runBlocking {
        val transport = GatedTransport(VpnClientConfig(text = "[Interface]", filename = "phone.conf"))
        val ops = AgentVPNClientOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6)
            .map { launch(Dispatchers.Default) { ops.configuration(ServiceID.WIREGUARD_VPN, "1") } }
            .forEach { it.join() }

        assertEquals(1, transport.highest, "fetching a configuration bypassed the gate")
    }

    // ----------------------------------------------------------- Refusals

    @Test
    fun `the server's own words survive as the error message`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse(
            "Vpn/ListVpnClients",
            code = "failed_precondition",
            text = "this server does not run shadowsocks",
        )

        val error = runCatching { ops(transport).list(ServiceID.SHADOWSOCKS) }.exceptionOrNull()

        assertTrue(error?.message.orEmpty().contains("does not run shadowsocks"), "${error?.message}")
    }

    // ------------------------------------------ What can have devices at all

    /**
     * The five protocols and nothing else: the panel manages devices, and it
     * manages exactly these. A sixth would have to arrive here first.
     */
    @Test
    fun `only the five protocols can have devices`() {
        assertEquals(ServiceID.VPN_PROTOCOLS, VPNClientProtocols.all.toSet())
        assertFalse(ServiceID.VPN_PANEL in VPNClientProtocols.all)
    }

    @Test
    fun `installed answers only with what this deployment actually has`() {
        assertEquals(
            listOf(ServiceID.WIREGUARD_VPN, ServiceID.OPEN_VPN),
            VPNClientProtocols.installed(setOf(ServiceID.OPEN_VPN, ServiceID.WIREGUARD_VPN, ServiceID.NEXTCLOUD)),
        )
        // Empty means there is nothing to show, not that something is wrong.
        assertTrue(VPNClientProtocols.installed(setOf(ServiceID.NEXTCLOUD)).isEmpty())
    }
}

package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNClientConfiguration
import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSDefaults
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSPriority
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/** The devices of one server's VPN */
class VPNClientsViewModelTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
        LicensePrompt.showing.value = false
    }

    private val wireguard = ServiceID.WIREGUARD_VPN
    private val shadowsocks = ServiceID.SHADOWSOCKS

    private val server = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = setOf(wireguard, shadowsocks),
        usesAgent = true,
    )

    private class Panel(
        var devices: MutableMap<ServiceID, MutableList<VPNClientDevice>> = mutableMapOf(),
        var failWith: Exception? = null,
        var dnsDefaults: VPNDNSDefaults = VPNDNSDefaults(),
    ) : VPNClientManaging {
        val asked = mutableListOf<String>()

        override suspend fun defaultDNS() = dnsDefaults

        override suspend fun list(protocol: ServiceID): List<VPNClientDevice> {
            asked += "list ${protocol.rawValue}"
            failWith?.let { throw it }
            return devices[protocol].orEmpty()
        }

        override suspend fun add(protocol: ServiceID, named: String, dns: List<String>): List<VPNClientDevice> {
            asked += "add ${protocol.rawValue} $named"
            failWith?.let { throw it }
            val settled = named.lowercase().replace(' ', '-').take(8)
            devices.getOrPut(protocol) { mutableListOf() }
                .add(VPNClientDevice(id = "id-$settled", name = settled, detail = "10.9.0.2/32"))
            return devices[protocol].orEmpty()
        }

        override suspend fun remove(protocol: ServiceID, clientID: String): List<VPNClientDevice> {
            asked += "remove ${protocol.rawValue} $clientID"
            failWith?.let { throw it }
            devices[protocol]?.removeAll { it.id == clientID }
            return devices[protocol].orEmpty()
        }

        override suspend fun setDNS(protocol: ServiceID, clientID: String, dns: List<String>): List<VPNClientDevice> {
            asked += "dns ${protocol.rawValue} $clientID ${dns.joinToString(",")}"
            failWith?.let { throw it }
            return devices[protocol].orEmpty()
        }

        override suspend fun configuration(protocol: ServiceID, clientID: String) =
            VPNClientConfiguration(text = "[Interface]", fileName = "$clientID.conf", qrIsUseful = true)
    }

    private fun model(panel: Panel, scope: CoroutineScope, onRelease: () -> Unit = {}) =
        VPNClientsViewModel(
            scope = scope,
            operations = { panel },
            release = { onRelease() },
        )

    @Test
    fun `the list shown is the one the panel answered with`() = runTest(StandardTestDispatcher()) {
        val panel = Panel(mutableMapOf(wireguard to mutableListOf(
            VPNClientDevice("id-1", "phone", "10.9.0.2/32")
        )))
        val model = model(panel, this)
        model.load(server, wireguard)
        runCurrent()
        assertEquals(listOf("phone"), model.state.value.devices.map { it.name })
        assertTrue(model.state.value.hasAnswered)
        assertNull(model.state.value.errorMessage)
    }

    @Test
    fun `the server's own resolver stays offered across protocols`() = runTest(StandardTestDispatcher()) {
        val panel = Panel(dnsDefaults = VPNDNSDefaults(listOf("10.53.0.53"), "10.53.0.53", listOf(ServiceID.ADGUARD_HOME)))
        val model = model(panel, this)
        model.loadDefaultDNS(server)
        runCurrent()
        model.load(server, shadowsocks)
        runCurrent()
        val local = model.state.value.localDNS
        assertTrue(local.isOffered)
        assertTrue(local.isChosen(model.state.value.defaultDNS))
        assertEquals("AdGuard Home", local.serviceNames)
    }

    @Test
    fun `the DNS order is shown as the agent keeps it and hidden when it cannot`() = runTest(StandardTestDispatcher()) {
        val kept = object : VPNClientManaging by Panel() {
            override suspend fun dnsPriority() = VPNDNSPriority(listOf("local", "9.9.9.9"), reachable = listOf(true, false))
            override suspend fun setDNSPriority(resolvers: List<String>) = VPNDNSPriority(resolvers)
        }
        val model = VPNClientsViewModel(scope = this, operations = { kept })
        model.loadDNSPriority(server)
        runCurrent()
        assertEquals(listOf("local", "9.9.9.9"), model.state.value.dnsPriority?.resolvers)
        model.setDNSPriority(server, listOf("9.9.9.9", "local"))
        runCurrent()
        assertEquals(listOf("9.9.9.9", "local"), model.state.value.dnsPriority?.resolvers)

        val silent = object : VPNClientManaging by Panel() {
            override suspend fun dnsPriority(): VPNDNSPriority = error("unimplemented")
        }
        val older = VPNClientsViewModel(scope = this, operations = { silent })
        older.loadDNSPriority(server)
        runCurrent()
        assertNull(older.state.value.dnsPriority)
    }

    @Test
    fun `a server's resolver is read without touching the shown list`() = runTest(StandardTestDispatcher()) {
        val defaults = VPNDNSDefaults(emptyList(), "10.53.0.53", listOf(ServiceID.PIHOLE))
        val model = model(Panel(dnsDefaults = defaults), this)
        assertEquals(defaults, model.dnsDefaultsOf(server))
        assertEquals(VPNDNSDefaults(), model.state.value.dnsDefaults)
    }

    @Test
    fun `an unreachable server still offers the resolver it offered before`() = runTest(StandardTestDispatcher()) {
        val defaults = VPNDNSDefaults(emptyList(), "10.53.0.53", listOf(ServiceID.ADGUARD_HOME))
        val memory = LocalDNSMemory.inMemory()
        var reachable = true
        val panel = Panel(dnsDefaults = defaults)
        val model = VPNClientsViewModel(
            scope = this,
            operations = { if (reachable) panel else error("no route to host") },
            localMemory = memory,
        )
        model.dnsDefaultsOf(server)
        reachable = false
        val recalled = model.dnsDefaultsOf(server)
        assertEquals("10.53.0.53", recalled?.localAddress)
        assertEquals(listOf(ServiceID.ADGUARD_HOME), recalled?.localServices)
        assertNull(LocalDNSMemory.inMemory().recall(server.id))
    }

    @Test
    fun `a device's new DNS is set on the panel, then its configuration read`() = runTest(StandardTestDispatcher()) {
        val panel = Panel()
        val model = model(panel, this)
        val configuration = model.changeDNS(server, wireguard, "id-1", listOf("9.9.9.9", "149.112.112.112"))
        assertEquals("id-1.conf", configuration?.fileName)
        assertEquals(listOf("dns ${wireguard.rawValue} id-1 9.9.9.9,149.112.112.112"), panel.asked)
    }

    @Test
    fun `a refused DNS change gives no configuration and says why`() = runTest(StandardTestDispatcher()) {
        var released = false
        val model = model(Panel(failWith = IllegalStateException("panel refused")), this) { released = true }
        assertNull(model.changeDNS(server, wireguard, "id-1", listOf("9.9.9.9")))
        assertEquals("panel refused", model.state.value.errorMessage)
        assertTrue(released)
    }

    @Test
    fun `an added device is shown under the name the panel settled on`() =
        runTest(StandardTestDispatcher()) {
            val panel = Panel()
            val model = model(panel, this)
            model.add(server, wireguard, "My Phone 12")
            runCurrent()
            assertEquals(listOf("my-phone"), model.state.value.devices.map { it.name })
            assertEquals("The device was added.", model.state.value.notice)
        }

    @Test
    fun `switching protocol empties the list before the new one arrives`() =
        runTest(StandardTestDispatcher()) {
            val panel = Panel(mutableMapOf(
                wireguard to mutableListOf(VPNClientDevice("id-1", "phone", "10.9.0.2/32")),
                shadowsocks to mutableListOf(VPNClientDevice("id-2", "laptop", "shadowsocks")),
            ))
            val model = model(panel, this)
            model.load(server, wireguard)
            runCurrent()
            model.load(server, shadowsocks)
            assertEquals(emptyList(), model.state.value.devices)
            assertEquals(shadowsocks, model.state.value.protocol)
            runCurrent()
            assertEquals(listOf("laptop"), model.state.value.devices.map { it.name })
        }

    @Test
    fun `a failed call keeps the devices it had and says why`() =
        runTest(StandardTestDispatcher()) {
            val panel = Panel(mutableMapOf(wireguard to mutableListOf(
                VPNClientDevice("id-1", "phone", "10.9.0.2/32")
            )))
            var released = 0
            val model = model(panel, this) { released += 1 }
            model.load(server, wireguard)
            runCurrent()
            panel.failWith = IllegalStateException("the agent bridge did not start: sudo: a password is required")
            model.remove(server, wireguard, "id-1")
            runCurrent()
            assertEquals(listOf("phone"), model.state.value.devices.map { it.name })
            assertTrue(model.state.value.errorMessage.orEmpty().contains("sudo"))
            assertNull(model.state.value.notice)
            assertEquals(1, released)
        }

    @Test
    fun `a failed configuration read answers null and explains itself`() =
        runTest(StandardTestDispatcher()) {
            val panel = object : VPNClientManaging {
                override suspend fun list(protocol: ServiceID) = emptyList<VPNClientDevice>()
                override suspend fun add(protocol: ServiceID, named: String, dns: List<String>) = emptyList<VPNClientDevice>()
                override suspend fun remove(protocol: ServiceID, clientID: String) = emptyList<VPNClientDevice>()
                override suspend fun configuration(protocol: ServiceID, clientID: String):
                    VPNClientConfiguration = throw IllegalStateException("no such client")
            }
            val model = VPNClientsViewModel(scope = this, operations = { panel })
            assertNull(model.configuration(server, wireguard, "id-9"))
            assertEquals("no such client", model.state.value.errorMessage)
        }

    @Test
    fun `a server that failed to answer is not reported as having no devices`() =
        runTest(StandardTestDispatcher()) {
            val panel = Panel(failWith = IllegalStateException(
                "the agent bridge did not start: Error: Connection refused (os error 111)"))
            val model = model(panel, this)
            model.load(server, wireguard)
            runCurrent()
            assertTrue(model.state.value.hasAnswered)
            assertTrue(model.state.value.devices.isEmpty())
            assertEquals(false, model.state.value.saysThereAreNone)
        }

    @Test
    fun `a server that answered with nothing is reported as having no devices`() =
        runTest(StandardTestDispatcher()) {
            val model = model(Panel(), this)
            model.load(server, wireguard)
            runCurrent()
            assertEquals(true, model.state.value.saysThereAreNone)
        }

    @Test
    fun `the protocol asked for is the one the caller named`() =
        runTest(StandardTestDispatcher()) {
            val panel = Panel()
            val model = model(panel, this)
            model.load(server, shadowsocks)
            runCurrent()
            model.add(server, shadowsocks, "laptop")
            runCurrent()
            assertEquals(
                listOf("list shadowsocks", "add shadowsocks laptop"),
                panel.asked,
            )
        }

    @Test
    fun `this phone reuses its own device, never another phone of the same name`() = runTest(StandardTestDispatcher()) {
        val panel = Panel(mutableMapOf(wireguard to mutableListOf(
            VPNClientDevice("other", "pixel", "10.9.0.2/32")
        )))
        val model = model(panel, this)
        val first = model.thisDeviceConfiguration(server, wireguard, "pixel")
        assertEquals("id-pixel.conf", first?.fileName)
        val again = model.thisDeviceConfiguration(server, wireguard, "pixel")
        assertEquals("id-pixel.conf", again?.fileName)
        assertEquals(1, panel.asked.count { it.startsWith("add") })
    }

    @Test
    fun `reading another protocol's devices leaves the shown list alone`() = runTest(StandardTestDispatcher()) {
        val panel = Panel(mutableMapOf(
            wireguard to mutableListOf(VPNClientDevice("id-1", "phone", "10.9.0.2/32")),
            shadowsocks to mutableListOf(VPNClientDevice("id-2", "tablet", "key")),
        ))
        val model = model(panel, this)
        model.load(server, wireguard)
        runCurrent()

        val others = model.devicesOf(server, shadowsocks)

        assertEquals(listOf("tablet"), others.map { it.name })
        assertEquals(listOf("phone"), model.state.value.devices.map { it.name })
    }

    @Test
    fun `an unreachable panel gives no devices and drops the session`() = runTest(StandardTestDispatcher()) {
        var released = 0
        val model = model(Panel(failWith = IllegalStateException("down")), this) { released += 1 }

        assertTrue(model.devicesOf(server, wireguard).isEmpty())
        assertEquals(1, released)
    }

    @Test
    fun `the own device id is the one remembered for that server and protocol`() = runTest(StandardTestDispatcher()) {
        val ids = OwnVpnDevices.inMemory().also { it.remember(server.id, wireguard.rawValue, "id-own") }
        val model = VPNClientsViewModel(this, { Panel() }, ownDevices = ids)

        assertEquals("id-own", model.ownClientId(server, wireguard))
        assertNull(model.ownClientId(server, shadowsocks))
    }

    @Test
    fun `a locked copy adds no device, shows no configuration and raises the lock`() =
        runTest(StandardTestDispatcher()) {
            LicenseGate.unlocked = false
            val panel = Panel()
            val model = model(panel, this)
            model.add(server, wireguard, "phone")
            runCurrent()
            assertTrue(panel.asked.isEmpty())
            assertNull(model.configuration(server, wireguard, "id-phone"))
            assertTrue(LicensePrompt.showing.value)
        }
}

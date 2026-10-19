package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import gryonixnexusd.v1.WakeOnLANInfo
import gryonixnexusd.v1.WakeSupport
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test

class WakeOnLANViewModelTests {
    private fun server(scope: DeploymentScope, host: String = "192.168.1.40") = Deployment(
        id = "S-1",
        name = "home",
        topology = Topology.SINGLE_HOST,
        domain = "lan.local",
        entry = HostEndpoint(host = host, user = "gryonix"),
        services = setOf(ServiceID.NEXTCLOUD),
        scope = scope,
    )

    @Test
    fun `the button is offered for a machine on the owner's own network`() {
        assertTrue(WakeOnLANViewModel.isOffered(server(DeploymentScope.LOCAL_ONLY)))
    }

    @Test
    fun `a machine at a home address is offered it whatever its scope`() {
        for (scope in DeploymentScope.entries) {
            assertTrue(WakeOnLANViewModel.isOffered(server(scope)), "$scope")
        }
        assertTrue(WakeOnLANViewModel.isOffered(server(DeploymentScope.PUBLIC_INTERNET, "draco.local")))
    }

    @Test
    fun `a rented server on a public address is not offered it`() {
        assertFalse(WakeOnLANViewModel.isOffered(server(DeploymentScope.PUBLIC_INTERNET, "203.0.113.10")))
        assertTrue(WakeOnLANViewModel.isOffered(server(DeploymentScope.DYNAMIC_DNS, "203.0.113.10")))
    }

    /**
     * **A stored MAC survives being written and read back.** The field is new
     * on [Deployment], and a deployment is JSON on disk — a field that does not
     * round-trip is a MAC somebody typed once and has to type again after every
     * launch.
     */
    @Test
    fun `the stored address survives the disk`() {
        val subject = server(DeploymentScope.LOCAL_ONLY).copy(wakeOnLANMAC = "aa:bb:cc:dd:ee:ff")
        val text = Json.encodeToString(Deployment.serializer(), subject)
        val decoded = Json.decodeFromString(Deployment.serializer(), text)
        assertEquals("aa:bb:cc:dd:ee:ff", decoded.wakeOnLANMAC)
    }

    /**
     * And a deployment written before the field existed still loads — every
     * fleet on every device is one of those.
     */
    @Test
    fun `a deployment written before the field existed still loads`() {
        val subject = server(DeploymentScope.LOCAL_ONLY)
        val text = Json.encodeToString(Deployment.serializer(), subject)
        assertFalse(text.contains("wakeOnLANMAC"), "the field is written even when absent")
        val decoded = Json { ignoreUnknownKeys = true }
            .decodeFromString(Deployment.serializer(), text)
        assertNull(decoded.wakeOnLANMAC)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun model(
        scope: TestScope,
        saved: MutableList<Deployment> = mutableListOf(),
        reading: WakeOnLANInfo? = null,
        sent: MutableList<String> = mutableListOf(),
    ) = WakeOnLANViewModel(
        scope = TestScope(UnconfinedTestDispatcher(scope.testScheduler)),
        runners = { error("no SSH in this test") },
        save = { saved += it },
        agentReading = { reading },
        sendFromPhone = { _, broadcast, _ -> sent += broadcast; true },
    )

    @Test
    fun `one tap sends to the stored address`() = runTest {
        val sent = mutableListOf<String>()
        val model = model(this, sent = sent)
        model.wake(server(DeploymentScope.LOCAL_ONLY).copy(wakeOnLANMAC = "aa:bb:cc:dd:ee:ff"))
        assertEquals(WakeOnLANViewModel.Note.SentFromPhone("192.168.1.255"), model.state.value.note)
        assertEquals(listOf("192.168.1.255"), sent)
    }

    @Test
    fun `without a stored address the agent's reading is used and kept`() = runTest {
        val saved = mutableListOf<Deployment>()
        val reading = WakeOnLANInfo(mac = "AA-BB-CC-DD-EE-01", broadcast = "192.168.1.127",
            support = WakeSupport.WAKE_SUPPORT_ARMED)
        val model = model(this, saved = saved, reading = reading)
        model.wake(server(DeploymentScope.LOCAL_ONLY).copy(usesAgent = true))
        assertEquals(WakeOnLANViewModel.Note.SentFromPhone("192.168.1.127"), model.state.value.note)
        assertEquals("aa:bb:cc:dd:ee:01", saved.single().wakeOnLANMAC)
    }

    @Test
    fun `a card that cannot wake is said so instead of sending`() = runTest {
        val sent = mutableListOf<String>()
        val reading = WakeOnLANInfo(mac = "aa:bb:cc:dd:ee:02", support = WakeSupport.WAKE_SUPPORT_UNSUPPORTED)
        val model = model(this, reading = reading, sent = sent)
        model.wake(server(DeploymentScope.LOCAL_ONLY).copy(usesAgent = true))
        assertEquals(WakeOnLANViewModel.Note.CardCannotWake, model.state.value.note)
        assertTrue(sent.isEmpty())
    }

    @Test
    fun `a machine never seen awake asks to be opened once`() = runTest {
        val model = model(this)
        model.wake(server(DeploymentScope.LOCAL_ONLY))
        assertEquals(WakeOnLANViewModel.Note.NoMACYet, model.state.value.note)
    }
}

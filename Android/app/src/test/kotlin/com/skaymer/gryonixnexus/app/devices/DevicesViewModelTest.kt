package com.skaymer.gryonixnexus.app.devices

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentcontrol.AgentDeviceOperations
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.catalog.Topology
import gryonixnexusd.v1.Device
import gryonixnexusd.v1.DeviceList
import gryonixnexusd.v1.SessionPolicy
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The paired-devices screen, which Android did not have at all */
private class StubTransport : com.skaymer.gryonixnexus.agentclient.AgentTransport {
    private val replies = mutableMapOf<String, Result<ByteArray>>()

    fun reply(path: String, message: com.squareup.wire.Message<*, *>) {
        replies[path] = Result.success(message.encode())
    }

    fun fail(path: String, error: Throwable) {
        replies[path] = Result.failure(error)
    }

    override suspend fun unary(path: String, request: ByteArray): ByteArray {
        val key = replies.keys.firstOrNull { path.endsWith(it) }
            ?: throw AgentError.Transport("nothing scripted for $path")
        return replies.getValue(key).getOrThrow()
    }

    override fun serverStream(path: String, request: ByteArray) =
        kotlinx.coroutines.flow.emptyFlow<ByteArray>()
}

class DevicesViewModelTest {
    private val deployment = Deployment(
        id = "D-1",
        name = "test",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
    )

    private fun device(id: String, uid: String = "", label: String = "", at: Long = 0) =
        Device(id = id, device_uid = uid, label = label, paired_at = at)

    private fun model(
        transport: StubTransport,
        scope: TestScope,
        uid: String = "",
    ) = DevicesViewModel(
        scope = scope,
        operations = { AgentDeviceOperations(AgentClient(transport)) },
        thisDeviceUID = { uid },
    )

    @Test
    fun `cancelled owner challenge never pairs and double tap challenges only once`() = runTest {
        var paired = 0
        var challenged = 0
        val vm = DevicesViewModel(this, operations = { error("must not call") }, enrol = { paired++ })
        vm.signInAgain(deployment) { challenged++; false }
        vm.signInAgain(deployment) { challenged++; true }
        advanceUntilIdle()
        assertEquals(1, challenged)
        assertEquals(0, paired)
        assertFalse(vm.state.value.signingIn)
    }

    @Test
    fun `confirmed owner pairs before reloading and failure remains retryable`() = runTest {
        val transport = StubTransport()
        transport.reply("ListDevices", DeviceList(devices = listOf(device("this", uid = "phone"))))
        transport.reply("GetSessionPolicy", SessionPolicy(auto_logout_months = 3))
        var paired = false
        val vm = DevicesViewModel(this, operations = {
            assertTrue(paired)
            AgentDeviceOperations(AgentClient(transport))
        }, enrol = { paired = true })
        vm.signInAgain(deployment) { true }
        advanceUntilIdle()
        assertEquals("this", vm.state.value.devices.single().id)
        assertFalse(vm.state.value.needsSignIn)
        assertEquals(3, vm.state.value.autoLogoutMonths)
        val failing = DevicesViewModel(this, operations = { error("must not list") }, enrol = { error("pair refused") })
        failing.signInAgain(deployment) { true }
        advanceUntilIdle()
        assertEquals("pair refused", failing.state.value.signInError)
        assertFalse(failing.state.value.signingIn)
    }

    // ------------------------------------------------------------- Loading

    @Test
    fun `the list comes back oldest first`() = runTest {
        val transport = StubTransport()
        transport.reply(
            "ListDevices",
            DeviceList(devices = listOf(device("b", at = 200), device("a", at = 100))),
        )
        transport.reply("GetSessionPolicy", SessionPolicy(auto_logout_months = 3))
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        assertEquals(listOf("a", "b"), vm.state.value.devices.map { it.id })
        assertEquals(3, vm.state.value.autoLogoutMonths)
        assertNull(vm.state.value.failure)
    }

    @Test
    fun `an agent without the policy verb still shows its devices`() = runTest {
        val transport = StubTransport()
        transport.reply("ListDevices", DeviceList(devices = listOf(device("a"))))
        transport.fail("GetSessionPolicy", AgentError.Rpc("not_found", "unknown route"))
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        assertEquals(listOf("a"), vm.state.value.devices.map { it.id })
        assertEquals(0, vm.state.value.autoLogoutMonths)
        assertNull(vm.state.value.failure)
    }

    @Test
    fun `an expired session is told apart from any other failure`() = runTest {
        val transport = StubTransport()
        transport.fail("ListDevices", AgentError.Rpc("unauthenticated", "session_expired: sign in again"))
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        assertTrue(vm.state.value.needsSignIn)
    }

    @Test
    fun `a device the server cannot identify is not offered a sign-in`() = runTest {
        val transport = StubTransport()
        transport.fail(
            "ListDevices",
            AgentError.Rpc("unauthenticated", "device_unidentified: update the app"),
        )
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        assertFalse(vm.state.value.needsSignIn, "there is no button that would help")
        assertEquals(DevicesViewModel.UNIDENTIFIED_MARKER, vm.state.value.failure,
                     "and the screen shows its own sentence, not the agent's")
    }

    @Test
    fun `an ordinary failure does not offer to sign in`() = runTest {
        val transport = StubTransport()
        transport.fail("ListDevices", AgentError.Transport("connection refused"))
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        assertFalse(vm.state.value.needsSignIn)
        assertTrue(vm.state.value.failure!!.contains("connection refused"))
    }

    // ------------------------------------------------------- Which row is us

    /** By device id, not by public key */
    @Test
    fun `this device is recognised by its id`() = runTest {
        val vm = model(StubTransport(), this, uid = "phone-a")
        assertTrue(vm.isThisDevice(device("1", uid = "phone-a")))
        assertFalse(vm.isThisDevice(device("2", uid = "phone-b")))
    }

    @Test
    fun `no id of our own marks no row`() = runTest {
        val vm = model(StubTransport(), this, uid = "")
        assertFalse(vm.isThisDevice(device("1", uid = "")))
    }

    // ------------------------------------------------------------ The term

    @Test
    fun `a saved term is the one the server confirmed`() = runTest {
        val transport = StubTransport()
        transport.reply("SetSessionPolicy", SessionPolicy(auto_logout_months = 6))
        val vm = model(transport, this)
        vm.setAutoLogout(deployment, 6)
        advanceUntilIdle()

        assertEquals(6, vm.state.value.autoLogoutMonths)
        assertFalse(vm.state.value.savingPolicy)
        assertNull(vm.state.value.policyError)
    }

    /** A refused term puts the old one back */
    @Test
    fun `a refused term goes back to what it was`() = runTest {
        val transport = StubTransport()
        transport.reply("ListDevices", DeviceList(devices = emptyList()))
        transport.reply("GetSessionPolicy", SessionPolicy(auto_logout_months = 3))
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        transport.fail("SetSessionPolicy", AgentError.Rpc("invalid_argument", "refused"))
        vm.setAutoLogout(deployment, 12)
        advanceUntilIdle()

        assertEquals(3, vm.state.value.autoLogoutMonths)
        assertTrue(vm.state.value.policyError!!.contains("refused"))
    }

    @Test
    fun `the offered terms are never one three six and twelve months`() {
        assertEquals(listOf(0, 1, 3, 6, 12), DevicesViewModel.OFFERED_MONTHS)
    }

    // ----------------------------------------------------------- Revoking

    @Test
    fun `a revoked device leaves the list`() = runTest {
        val transport = StubTransport()
        transport.reply("ListDevices", DeviceList(devices = listOf(device("a"), device("b"))))
        transport.reply("GetSessionPolicy", SessionPolicy())
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        transport.reply("Revoke", gryonixnexusd.v1.RevokeResponse(revoked = true))
        vm.revoke(deployment, device("a"))
        advanceUntilIdle()

        assertEquals(listOf("b"), vm.state.value.devices.map { it.id })
        assertNull(vm.state.value.revoking)
    }

    /** A refused revoke leaves the row where it is */
    @Test
    fun `a refused revoke keeps the row and says why`() = runTest {
        val transport = StubTransport()
        transport.reply("ListDevices", DeviceList(devices = listOf(device("a"))))
        transport.reply("GetSessionPolicy", SessionPolicy())
        val vm = model(transport, this)
        vm.load(deployment)
        advanceUntilIdle()

        transport.fail("Revoke", AgentError.Rpc("internal", "could not write the register"))
        vm.revoke(deployment, device("a"))
        advanceUntilIdle()

        assertEquals(listOf("a"), vm.state.value.devices.map { it.id })
        assertTrue(vm.state.value.revokeError!!.contains("could not write"))
    }
}

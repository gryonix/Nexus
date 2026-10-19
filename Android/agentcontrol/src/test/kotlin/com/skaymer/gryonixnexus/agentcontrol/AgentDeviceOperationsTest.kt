package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.Device
import gryonixnexusd.v1.DeviceList
import gryonixnexusd.v1.RevokeRequest
import gryonixnexusd.v1.RevokeResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentDeviceOperationsTests` */
class AgentDeviceOperationsTest {
    private fun devices(vararg rows: Device) = DeviceList(devices = rows.toList())

    private fun ops(transport: FakeAgentTransport) = AgentDeviceOperations(AgentClient(transport))

    // -------------------------------------------------------- ListDevices

    @Test
    fun `devices come back with label and paired at`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Pairing/ListDevices",
            devices(
                Device(
                    id = "abc123",
                    public_key = "ssh-ed25519 AAAA...",
                    label = "Morgan's iPhone",
                    paired_at = 1_700_000_000_000,
                ),
            ),
        )

        val result = ops(transport).listDevices()

        assertEquals(listOf("/gryonixnexusd.v1.Pairing/ListDevices"), transport.paths)
        assertEquals(1, result.size)
        assertEquals("abc123", result[0].id)
        assertEquals("Morgan's iPhone", result[0].label)
        assertEquals("ssh-ed25519 AAAA...", result[0].public_key)
        assertEquals(1_700_000_000_000, result[0].paired_at)
    }

    @Test
    fun `no devices yet is an empty list not a failure`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Pairing/ListDevices", devices())
        assertTrue(ops(transport).listDevices().isEmpty())
    }

    @Test
    fun `multiple devices all come back in order`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Pairing/ListDevices",
            devices(
                Device(id = "a", public_key = "key-a", label = "Mac", paired_at = 1),
                Device(id = "b", public_key = "key-b", label = "iPad", paired_at = 2),
            ),
        )
        assertEquals(listOf("a", "b"), ops(transport).listDevices().map { it.id })
    }

    // ------------------------------------------------------------- Revoke

    @Test
    fun `revoke sends the device id and reports success`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Pairing/Revoke", RevokeResponse(revoked = true))

        assertTrue(ops(transport).revoke("abc123"))

        assertEquals(listOf("/gryonixnexusd.v1.Pairing/Revoke"), transport.paths)
        assertEquals("abc123", RevokeRequest.ADAPTER.decode(transport.calls.first().second).device_id)
    }

    @Test
    fun `revoking an already gone device reports false rather than throwing`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Pairing/Revoke", RevokeResponse(revoked = false))
        assertFalse(ops(transport).revoke("unknown"))
    }

    // ---------------------------------------------------------- Refusals

    @Test
    fun `the server's own words survive as the error message`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse("Pairing/Revoke", code = "not_found", text = "no such device")

        val error = runCatching { ops(transport).revoke("ghost") }.exceptionOrNull()
        assertTrue(error?.message.orEmpty().contains("no such device"), "${error?.message}")
    }

    // ---------------------------------------------------------- The gate

    /**
     * Narrower than [AgentChannelGateTest], which proves the gate holds its
     * ceiling: this proves [AgentDeviceOperations] actually THREADS the gate it
     * was handed rather than accepting one and ignoring it. Paired with the
     * ungated case below, which is the harness's own negative control.
     */
    @Test
    fun `concurrent calls are serialized by a provided gate`() = runBlocking {
        val transport = GatedTransport(DeviceList())
        val ops = AgentDeviceOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6).map { launch(Dispatchers.Default) { ops.listDevices() } }.forEach { it.join() }

        assertEquals(1, transport.highest, "more than one call ran at once under a limit-1 gate")
    }

    @Test
    fun `with no gate calls genuinely overlap`() = runBlocking {
        val transport = GatedTransport(DeviceList())
        val ops = AgentDeviceOperations(AgentClient(transport))

        (0 until 6).map { launch(Dispatchers.Default) { ops.listDevices() } }.forEach { it.join() }

        assertTrue(
            transport.highest > 1,
            "calls did not overlap even without a gate — the harness is not sensitive",
        )
    }
}

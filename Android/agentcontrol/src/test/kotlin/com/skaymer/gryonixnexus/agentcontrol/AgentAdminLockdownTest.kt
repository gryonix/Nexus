package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.LockdownRouting
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import gryonixnexusd.v1.LockdownMode
import gryonixnexusd.v1.LockdownState
import gryonixnexusd.v1.SetLockdownRequest
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentAdminLockdownTests` */
class AgentAdminLockdownTest {
    private fun state(mode: LockdownMode, hosts: List<String> = emptyList()) =
        LockdownState(mode = mode, hosts = hosts)

    private fun ops(transport: FakeAgentTransport) = AgentAdminLockdown(AgentClient(transport))

    private fun FakeAgentTransport.sentSet(): SetLockdownRequest =
        SetLockdownRequest.ADAPTER.decode(calls.last { it.first.endsWith("SetLockdown") }.second)

    // ------------------------------------------------------------- Routing

    @Test
    fun `lockdown follows the same route as control actions with no extra condition`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            LockdownRouting.route(usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            LockdownRouting.route(usesAgent = true, agentTransportAvailable = false),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            LockdownRouting.route(usesAgent = false, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            LockdownRouting.route(usesAgent = false, agentTransportAvailable = false),
        )
    }

    // -------------------------------------------------------------- status

    @Test
    fun `status maps each mode and calls the right path`() = runTest {
        val expected = mapOf(
            LockdownMode.LOCKDOWN_MODE_OFF to AdminLockdownState.Off,
            LockdownMode.LOCKDOWN_MODE_ALL to AdminLockdownState.All,
        )
        for ((wire, want) in expected) {
            val transport = FakeAgentTransport()
            transport.reply("Lockdown/GetLockdown", state(wire))
            assertEquals(want, ops(transport).status())
            assertEquals(listOf("/gryonixnexusd.v1.Lockdown/GetLockdown"), transport.paths)
        }
    }

    @Test
    fun `status maps only mode to its host set`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Lockdown/GetLockdown",
            state(LockdownMode.LOCKDOWN_MODE_ONLY, listOf("a.example.com", "b.example.com")),
        )
        assertEquals(
            AdminLockdownState.Only(setOf("a.example.com", "b.example.com")),
            ops(transport).status(),
        )
    }

    @Test
    fun `an unrecognised mode from a newer server reads as off`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Lockdown/GetLockdown", state(LockdownMode.LOCKDOWN_MODE_UNSPECIFIED))
        assertEquals(AdminLockdownState.Off, ops(transport).status())
    }

    @Test
    fun `set true sends all and reads the wrapper's answer back`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Lockdown/SetLockdown", state(LockdownMode.LOCKDOWN_MODE_ALL))

        val result = ops(transport).set(true)

        assertEquals(listOf("/gryonixnexusd.v1.Lockdown/SetLockdown"), transport.paths)
        assertEquals(LockdownMode.LOCKDOWN_MODE_ALL, transport.sentSet().mode)
        assertEquals(AdminLockdownState.All, result)
    }

    @Test
    fun `set false sends off`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Lockdown/SetLockdown", state(LockdownMode.LOCKDOWN_MODE_OFF))
        ops(transport).set(false)
        assertEquals(LockdownMode.LOCKDOWN_MODE_OFF, transport.sentSet().mode)
    }

    // ----------------------------------------------------------- set(hosts)

    @Test
    fun `set hosts sends only with the valid hosts`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Lockdown/SetLockdown",
            state(LockdownMode.LOCKDOWN_MODE_ONLY, listOf("a.example.com")),
        )

        val result = ops(transport).set(listOf("a.example.com"))

        assertEquals(LockdownMode.LOCKDOWN_MODE_ONLY, transport.sentSet().mode)
        assertEquals(listOf("a.example.com"), transport.sentSet().hosts)
        assertEquals(AdminLockdownState.Only(setOf("a.example.com")), result)
    }

    @Test
    fun `an invalid host refuses the whole change instead of guarding less`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Lockdown/SetLockdown", state(LockdownMode.LOCKDOWN_MODE_OFF))

        for (hosts in listOf(listOf("a.example.com", "evil;rm -rf /"), listOf("evil;rm -rf /"))) {
            val error = runCatching { ops(transport).set(hosts) }.exceptionOrNull()
            assertTrue(error is ServerControlError.CommandFailed, "got $error")
        }
    }

    @Test
    fun `an empty list still means off`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Lockdown/SetLockdown", state(LockdownMode.LOCKDOWN_MODE_OFF))

        assertEquals(AdminLockdownState.Off, ops(transport).set(emptyList()))
        assertEquals(LockdownMode.LOCKDOWN_MODE_OFF, transport.sentSet().mode)
    }

    // --------------------------------------------------- Failure surfacing

    @Test
    fun `an RPC failure surfaces as command failed`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse(
            "Lockdown/GetLockdown",
            code = "failed_precondition",
            text = "this server has no lockdown wrapper",
        )

        val error = runCatching { ops(transport).status() }.exceptionOrNull()

        assertTrue(error is ServerControlError.CommandFailed, "got $error")
        assertEquals("this server has no lockdown wrapper", error.stderr)
    }
}

package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.VaultwardenTwoFactor
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `VaultwardenTwoFactorStatusTests` */
class AgentVaultwardenOperationsTest {
    private fun ops(transport: FakeAgentTransport) = AgentVaultwardenOperations(AgentClient(transport))

    @Test
    fun `an unreadable database gives no status`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Vaultwarden/GetVaultwardenTwoFactor", VaultwardenTwoFactor(readable = false, users = 3))

        assertNull(ops(transport).twoFactor())
        assertEquals(listOf("/gryonixnexusd.v1.Vaultwarden/GetVaultwardenTwoFactor"), transport.paths)
    }

    @Test
    fun `an account without two-factor needs attention`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Vaultwarden/GetVaultwardenTwoFactor",
            VaultwardenTwoFactor(readable = true, users = 4, users_without_two_factor = 1),
        )

        val status = ops(transport).twoFactor()

        assertEquals(VaultwardenTwoFactorStatus(users = 4, usersWithoutTwoFactor = 1), status)
        assertTrue(status!!.needsAttention)
    }

    @Test
    fun `everyone with two-factor needs no attention`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Vaultwarden/GetVaultwardenTwoFactor",
            VaultwardenTwoFactor(readable = true, users = 2, users_without_two_factor = 0),
        )

        assertFalse(ops(transport).twoFactor()!!.needsAttention)
    }
}

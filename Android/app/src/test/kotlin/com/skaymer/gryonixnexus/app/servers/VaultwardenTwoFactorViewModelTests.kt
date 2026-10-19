package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.agentcontrol.AgentVaultwardenOperations
import com.skaymer.gryonixnexus.agentcontrol.VaultwardenTwoFactorStatus
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import gryonixnexusd.v1.VaultwardenTwoFactor
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Which Vaultwarden accounts lack two-factor login */
@OptIn(ExperimentalCoroutinesApi::class)
class VaultwardenTwoFactorViewModelTests {
    private fun server(usesAgent: Boolean = true, services: Set<ServiceID> = setOf(ServiceID.VAULTWARDEN)) =
        Deployment(
            id = "S-1",
            name = "vault",
            topology = Topology.SINGLE_HOST,
            domain = "example.test",
            entry = HostEndpoint(host = "203.0.113.40", user = "root"),
            services = services,
            usesAgent = usesAgent,
        )

    private class Answering(private val reply: () -> ByteArray) : AgentTransport {
        override suspend fun unary(path: String, request: ByteArray): ByteArray = reply()
        override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = emptyFlow()
    }

    private fun model(scope: TestScope, reply: () -> ByteArray) = VaultwardenTwoFactorViewModel(
        scope = scope,
        operations = { AgentVaultwardenOperations(AgentClient(Answering(reply))) },
    )

    @Test
    fun `only an agent server running Vaultwarden shows the row`() {
        assertTrue(VaultwardenTwoFactorViewModel.canShow(server()))
        assertFalse(VaultwardenTwoFactorViewModel.canShow(server(usesAgent = false)))
        assertFalse(VaultwardenTwoFactorViewModel.canShow(server(services = emptySet())))
    }

    @Test
    fun `the answer is kept per server`() {
        val scope = TestScope(UnconfinedTestDispatcher())
        val answer = VaultwardenTwoFactor(readable = true, users = 3, users_without_two_factor = 2)
        val model = model(scope) { answer.encode() }

        model.load(server())

        assertEquals(VaultwardenTwoFactorStatus(3, 2), model.state.value["S-1"])
    }

    @Test
    fun `a failing agent leaves an empty answer for that server`() {
        val scope = TestScope(UnconfinedTestDispatcher())
        val model = model(scope) { error("agent unreachable") }

        model.load(server())

        assertTrue(model.state.value.containsKey("S-1"))
        assertNull(model.state.value["S-1"])
    }
}

package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAutoRules
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import gryonixnexusd.v1.SetSecurityAutoRulesRequest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class SecurityViewModelTests {
    private fun server(usesAgent: Boolean = true) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = emptySet(),
        usesAgent = usesAgent,
    )

    @Test
    fun `the card is shown only for an agent server`() {
        assertTrue(SecurityViewModel.canShow(server(usesAgent = true), agentTransportAvailable = true))
        assertFalse(SecurityViewModel.canShow(server(usesAgent = false), agentTransportAvailable = true))
        assertFalse(SecurityViewModel.canShow(server(usesAgent = true), agentTransportAvailable = false))
    }

    @Test
    fun `compact reads big counts as scale`() {
        assertEquals("42", SecurityViewModel.compact(42))
        assertEquals("15.7k", SecurityViewModel.compact(15_737))
        assertEquals("21.0k", SecurityViewModel.compact(21_029))
        assertEquals("128k", SecurityViewModel.compact(128_000))
        assertEquals("1.2M", SecurityViewModel.compact(1_200_000))
    }

    @Test
    fun `flag maps a country code and drops a bad one`() {
        assertEquals("🇷🇺", SecurityViewModel.flag("RU"))
        assertEquals("", SecurityViewModel.flag(""))
        assertEquals("", SecurityViewModel.flag("XYZ"))
    }

    @Test
    fun `scenario names are made readable with a safe fallback`() {
        assertEquals("SSH brute force", HostSecurityStatus.Scenario("crowdsecurity/ssh-bf", 1).readableName)
        assertEquals("Some New Thing", HostSecurityStatus.Scenario("acme/some-new-thing", 1).readableName)
    }

    /** Holds the first call until released, then answers it */
    private class HeldTransport : AgentTransport {
        val sent = mutableListOf<List<String>>()
        private var hold: CompletableDeferred<Unit>? = CompletableDeferred()

        override suspend fun unary(path: String, request: ByteArray): ByteArray {
            val rules = checkNotNull(SetSecurityAutoRulesRequest.ADAPTER.decode(request).rules)
            sent += rules.countries
            hold?.let {
                it.await()
                hold = null
            }
            return rules.encode()
        }

        override fun serverStream(path: String, request: ByteArray) = emptyFlow<ByteArray>()

        fun release() {
            hold?.complete(Unit)
        }
    }

    @Test
    fun `an edit made during a save is sent after it`() = runTest(StandardTestDispatcher()) {
        val transport = HeldTransport()
        val model = SecurityViewModel(
            scope = this,
            operations = { AgentSecurityOperations(AgentClient(transport)) },
        )
        model.saveAutoRules(server(), HostSecurityAutoRules(isOn = true, countries = listOf("RU")))
        runCurrent()
        model.saveAutoRules(
            server(),
            HostSecurityAutoRules(isOn = true, countries = listOf("RU", "CN")),
        )
        runCurrent()
        assertEquals(listOf(listOf("RU")), transport.sent)

        transport.release()
        runCurrent()
        assertEquals(listOf(listOf("RU"), listOf("RU", "CN")), transport.sent)
        assertEquals(listOf("RU", "CN"), model.state.value.autoRules?.countries)
        assertFalse(model.state.value.autoRulesBusy)
    }
}

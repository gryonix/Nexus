package com.skaymer.gryonixnexus.app.dns

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.DKIMManaging
import com.skaymer.gryonixnexus.servercontrol.DKIMRecord
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The DKIM records a mail server minted */
class DKIMViewModelTests {
    private fun server(services: Set<ServiceID>) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
    )

    private class Scripted(
        val records: List<DKIMRecord> = emptyList(),
        val fail: Boolean = false,
    ) : DKIMManaging {
        override suspend fun fetchRecords(): List<DKIMRecord> {
            if (fail) throw IOException("the wrapper is not installed")
            return records
        }
    }

    @Test
    fun `only a server that sends mail is offered the records`() {
        assertTrue(DKIMViewModel.hasMailEngine(server(setOf(ServiceID.MAILCOW))))
        assertTrue(DKIMViewModel.hasMailEngine(server(setOf(ServiceID.DOCKER_MAILSERVER))))
        assertFalse(DKIMViewModel.hasMailEngine(server(setOf(ServiceID.NEXTCLOUD))))
    }

    @Test
    fun `an empty answer is a wait, and a failed one is not`() = runTest(StandardTestDispatcher()) {
        val waiting = DKIMViewModel(this, { Scripted() })
        waiting.load(server(setOf(ServiceID.MAILCOW)))
        runCurrent()
        assertTrue(waiting.state.value.saysTheKeyIsNotReady)

        val broken = DKIMViewModel(this, { Scripted(fail = true) })
        broken.load(server(setOf(ServiceID.MAILCOW)))
        runCurrent()
        // Answered and empty too — and NOT the same news.
        assertFalse(broken.state.value.saysTheKeyIsNotReady)
        assertEquals("the wrapper is not installed", broken.state.value.errorMessage)
    }

    @Test
    fun `the records are copied in the shape a DNS panel takes`() =
        runTest(StandardTestDispatcher()) {
            val model = DKIMViewModel(
                this,
                { Scripted(listOf(DKIMRecord("dkim._domainkey.example.test", "v=DKIM1;k=rsa;p=AAA"))) },
            )
            model.load(server(setOf(ServiceID.MAILCOW)))
            runCurrent()

            assertEquals(
                "TXT\tdkim._domainkey.example.test\tv=DKIM1;k=rsa;p=AAA",
                model.state.value.copyText(),
            )
        }
}

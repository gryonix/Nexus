package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.GetLocalRootCAResponse
import gryonixnexusd.v1.PortProbe
import gryonixnexusd.v1.ProbePublicPortsRequest
import gryonixnexusd.v1.ProbePublicPortsResponse
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class AgentExposureTest {
    @Test
    fun `only the open ports come back and only the asked ports are sent`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Exposure/ProbePublicPorts",
            ProbePublicPortsResponse(ports = listOf(PortProbe(port = 25, open_ = true), PortProbe(port = 993, open_ = false))),
        )
        val open = AgentExposure(AgentClient(transport)).openPorts("203.0.113.9", listOf(25, 993))
        assertEquals(listOf(25), open)
        val sent = ProbePublicPortsRequest.ADAPTER.decode(transport.calls.last().second)
        assertEquals(listOf(25, 993), sent.ports)
        assertEquals("203.0.113.9", sent.host)
    }

    @Test
    fun `the root certificate comes back as text`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Exposure/GetLocalRootCA", GetLocalRootCAResponse(pem = "-----BEGIN CERTIFICATE-----"))
        assertEquals("-----BEGIN CERTIFICATE-----", AgentExposure(AgentClient(transport)).localRootCA())
        assertEquals(listOf("/gryonixnexusd.v1.Exposure/GetLocalRootCA"), transport.paths)
    }
}

package com.skaymer.gryonixnexus.agentclient

import com.squareup.wire.Message
import gryonixnexusd.v1.Device
import gryonixnexusd.v1.DiscoverResult
import gryonixnexusd.v1.HostMetricsRequest
import gryonixnexusd.v1.MetricsSample
import gryonixnexusd.v1.PairRequest
import gryonixnexusd.v1.PairResponse
import gryonixnexusd.v1.Service
import gryonixnexusd.v1.ServiceStatus
import gryonixnexusd.v1.State
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The typed client's own encode/decode, above the framing */
class AgentClientTest {
    private class Mock(
        val onUnary: (String, ByteArray) -> ByteArray = { _, _ -> ByteArray(0) },
        val onStream: (String, ByteArray) -> Flow<ByteArray> = { _, _ -> flow { } },
    ) : AgentTransport {
        val paths = mutableListOf<String>()
        val requests = mutableListOf<ByteArray>()

        override suspend fun unary(path: String, request: ByteArray): ByteArray {
            paths += path
            requests += request
            return onUnary(path, request)
        }

        override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> {
            paths += path
            requests += request
            return onStream(path, request)
        }
    }

    private fun bytes(message: Message<*, *>) = message.encode()

    // -------------------------------------------------------------- getState

    @Test
    fun `get state names its path and decodes the state back`() = runTest {
        val response = bytes(
            State(
                agent_version = "1.2.3",
                services = listOf(Service(id = "mailcow", status = ServiceStatus.SERVICE_STATUS_RUNNING)),
            ),
        )
        val transport = Mock(onUnary = { _, _ -> response })

        val state = AgentClient(transport).getState()

        assertEquals(listOf("/gryonixnexusd.v1.Control/GetState"), transport.paths)
        assertEquals("1.2.3", state.agent_version)
        assertEquals("mailcow", state.services.first().id)
        assertEquals(ServiceStatus.SERVICE_STATUS_RUNNING, state.services.first().status)
    }

    // -------------------------------------------------------------- discover

    @Test
    fun `discover names its path and carries the services it found`() = runTest {
        val response = bytes(
            DiscoverResult(
                services = listOf(
                    Service(id = "mailcow", status = ServiceStatus.SERVICE_STATUS_RUNNING),
                    Service(id = "vaultwarden", status = ServiceStatus.SERVICE_STATUS_STOPPED),
                ),
                notes = listOf("caddy is running but was not installed by this app"),
            ),
        )
        val transport = Mock(onUnary = { _, _ -> response })

        val found = AgentClient(transport).discover()

        assertEquals(listOf("/gryonixnexusd.v1.Control/Discover"), transport.paths)
        assertEquals(listOf("mailcow", "vaultwarden"), found.services.map { it.id })
        assertEquals(ServiceStatus.SERVICE_STATUS_STOPPED, found.services.last().status)
        assertEquals(1, found.notes.size)
    }

    // ------------------------------------------------------------------ pair

    @Test
    fun `pair sends its fields and returns the device`() = runTest {
        val response = bytes(PairResponse(device = Device(id = "dev-abc", scopes = listOf("read"))))
        val transport = Mock(onUnary = { _, _ -> response })

        val device = AgentClient(transport)
            .pair(code = "ABCD-1234", devicePublicKey = "ssh-ed25519 AAAA", label = "iPhone", deviceUID = "phone-uid")

        assertEquals(listOf("/gryonixnexusd.v1.Pairing/Pair"), transport.paths)
        val sent = PairRequest.ADAPTER.decode(transport.requests.first())
        assertEquals("ABCD-1234", sent.code)
        assertEquals("iPhone", sent.label)
        assertEquals("phone-uid", sent.device_uid)
        assertEquals("ssh-ed25519 AAAA", sent.device_public_key)
        assertEquals("dev-abc", device.id)
        assertEquals(listOf("read"), device.scopes)
    }

    @Test
    fun `an rpc error propagates rather than becoming an empty answer`() = runTest {
        val transport = Mock(
            onUnary = { _, _ -> throw AgentError.Rpc("permission_denied", "invalid or expired pairing code") },
        )

        val error = runCatching {
            AgentClient(transport).pair(code = "WRONG", devicePublicKey = "k", label = "l")
        }.exceptionOrNull()

        assertTrue(error is AgentError.Rpc, "got $error")
        assertEquals("permission_denied", error.code)
    }

    // ----------------------------------------------------------- hostMetrics

    @Test
    fun `the host metrics stream decodes every sample`() = runTest {
        val samples = listOf(
            bytes(MetricsSample(cpu_percent = 10.0)),
            bytes(MetricsSample(cpu_percent = 20.0)),
        )
        val transport = Mock(onStream = { _, _ -> flow { samples.forEach { emit(it) } } })

        val seen = AgentClient(transport).hostMetrics(intervalSeconds = 1).toList()

        assertEquals(listOf("/gryonixnexusd.v1.Control/HostMetrics"), transport.paths)
        assertEquals(listOf(10.0, 20.0), seen.map { it.cpu_percent })
    }

    @Test
    fun `the sampling interval travels in the request`() = runTest {
        val transport = Mock(onStream = { _, _ -> flow { } })

        AgentClient(transport).hostMetrics(intervalSeconds = 5).toList()

        assertEquals(5, HostMetricsRequest.ADAPTER.decode(transport.requests.first()).interval_seconds)
    }

    @Test
    fun `a stream that yields nothing ends cleanly`() = runTest {
        val transport = Mock(onStream = { _, _ -> flow { } })
        assertTrue(AgentClient(transport).hostMetrics().toList().isEmpty())
    }
}

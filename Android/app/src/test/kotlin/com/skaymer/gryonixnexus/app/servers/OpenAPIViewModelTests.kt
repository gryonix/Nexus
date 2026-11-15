package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentcontrol.OpenAPIAccess
import com.skaymer.gryonixnexus.agentcontrol.OpenAPISite
import com.skaymer.gryonixnexus.catalog.ServiceAPIGroups
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Several API switches applied in one request */
class OpenAPIViewModelTests {
    private val id = ServiceID.VAULTWARDEN

    private val server = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        usesAgent = true,
    )

    private class FakeAccess(var paths: List<String>) : OpenAPIAccess {
        val asked = mutableListOf<List<String>>()

        override suspend fun sites(): Map<String, OpenAPISite> =
            mapOf("vaultwarden" to OpenAPISite("vaultwarden", paths, editable = true))

        override suspend fun set(serviceID: String, paths: List<String>): Map<String, OpenAPISite> {
            asked += paths
            this.paths = paths
            return sites()
        }
    }

    @Test
    fun `the waiting switches go to the server in one request`() = runTest {
        val access = FakeAccess(emptyList())
        val model = OpenAPIViewModel(CoroutineScope(StandardTestDispatcher(testScheduler))) { access }
        model.refresh(server)
        runCurrent()
        val group = ServiceAPIGroups.groups(id).first()
        assertFalse(model.state.value.isOpen(group, id))

        model.setGroups(server, id, mapOf(group.id to true))
        runCurrent()
        assertEquals(1, access.asked.size)
        assertTrue(access.asked.single().containsAll(group.paths))
        assertTrue(model.state.value.isOpen(group, id))
    }

    @Test
    fun `closing a group takes its paths away and keeps the rest`() = runTest {
        val group = ServiceAPIGroups.groups(id).first()
        val access = FakeAccess(group.paths + "/kept-by-hand")
        val model = OpenAPIViewModel(CoroutineScope(StandardTestDispatcher(testScheduler))) { access }
        model.refresh(server)
        runCurrent()
        assertTrue(model.state.value.isOpen(group, id))

        model.setGroups(server, id, mapOf(group.id to false))
        runCurrent()
        assertEquals(listOf("/kept-by-hand"), access.asked.single())
        assertFalse(model.state.value.isOpen(group, id))
    }
}

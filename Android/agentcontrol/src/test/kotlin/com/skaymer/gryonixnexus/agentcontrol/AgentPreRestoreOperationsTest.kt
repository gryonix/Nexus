package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import gryonixnexusd.v1.DeletePreRestoreCopyRequest
import gryonixnexusd.v1.ListPreRestoreCopiesRequest
import gryonixnexusd.v1.PreRestoreCopy as WireCopy
import gryonixnexusd.v1.PreRestoreCopyList
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentPreRestoreOperationsTests` */
class AgentPreRestoreOperationsTest {
    private fun wire(path: String, bytes: Long, at: Long, known: Boolean = true) = WireCopy(
        service_id = "nextcloud",
        path = path,
        size_bytes = bytes,
        size_known = known,
        moved_aside_unix = at,
    )

    @Test
    fun `the list asks for one service and comes back newest first`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Restore/ListPreRestoreCopies",
            PreRestoreCopyList(
                copies = listOf(
                    wire("/opt/nextcloud/data.pre-restore-20260901-100000", 5_000, 1_788_000_000),
                    wire("/opt/nextcloud/data.pre-restore-20261001-100000", 9_000, 1_790_000_000),
                ),
            ),
        )
        val service = checkNotNull(ServiceRegistry.service(ServiceID.NEXTCLOUD))

        val copies = AgentPreRestoreOperations(AgentClient(transport)).copies(service)

        assertEquals(listOf("/gryonixnexusd.v1.Restore/ListPreRestoreCopies"), transport.paths)
        assertEquals(
            "nextcloud",
            ListPreRestoreCopiesRequest.ADAPTER.decode(transport.calls.first().second).service_id,
        )
        assertEquals(listOf(9_000L, 5_000L), copies.map { it.sizeBytes })
        assertEquals("data.pre-restore-20261001-100000", copies.first().name)
    }

    @Test
    fun `deleting sends the copy's own path and returns what is left`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Restore/DeletePreRestoreCopy", PreRestoreCopyList())
        val target = PreRestoreCopy(
            serviceID = "nextcloud",
            path = "/opt/nextcloud/data.pre-restore-20261001-100000",
            sizeBytes = 9_000,
            sizeKnown = true,
            movedAsideSeconds = 1,
        )

        val left = AgentPreRestoreOperations(AgentClient(transport)).delete(target)

        assertEquals(listOf("/gryonixnexusd.v1.Restore/DeletePreRestoreCopy"), transport.paths)
        assertEquals(
            target.path,
            DeletePreRestoreCopyRequest.ADAPTER.decode(transport.calls.first().second).path,
        )
        assertTrue(left.isEmpty())
    }

    @Test
    fun `a size that ran out of time is flagged unknown`() {
        val list = PreRestoreCopyList(
            copies = listOf(wire("/srv/a.pre-restore-1", 10, 1), wire("/srv/b.pre-restore-1", 0, 1, known = false)),
        )
        val copies = AgentPreRestoreOperations.newestFirst(list)
        assertTrue(copies.first { it.name.startsWith("a") }.sizeKnown)
        assertFalse(copies.first { it.name.startsWith("b") }.sizeKnown)
    }
}

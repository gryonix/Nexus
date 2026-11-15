package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.ServerSection
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AlertTapTests {
    private fun gnx(vararg pairs: Pair<String, String>) = JsonObject(pairs.associate { it.first to JsonPrimitive(it.second) })

    private fun tap(data: JsonObject?, title: String? = "Title") =
        AlertTap.of(data, title, "Body") { if (it == "srv") "S-1" else null }

    @Test
    fun `an alert about a run names the run and its server`() {
        val found = tap(gnx("server_id" to "srv", "kind" to "gnx.alert.operation.failed", "job_id" to "job-1"))
        assertEquals("job-1", found.jobID)
        assertEquals("S-1", found.destination?.deploymentID)
        assertNull(found.card)
    }

    @Test
    fun `an empty run id is not a run`() {
        assertNull(tap(gnx("server_id" to "srv", "kind" to "gnx.alert.operation", "job_id" to "")).jobID)
    }

    @Test
    fun `a problem alert carries its card and its server`() {
        val found = tap(gnx("server_id" to "srv", "kind" to "gnx.alert.space"), title = "Disk almost full")
        assertEquals(AlertCard("Disk almost full", "Body", "gnx.alert.space"), found.card)
        assertEquals(AlertDestination("S-1", ServerSection.GENERAL), found.destination)
        assertNull(found.jobID)
    }

    @Test
    fun `other alerts open the server and an unknown server opens nothing`() {
        val login = tap(gnx("server_id" to "srv", "kind" to "gnx.alert.ssh_login"))
        assertEquals(AlertDestination("S-1", ServerSection.GENERAL), login.destination)
        assertNull(login.card)
        assertNull(tap(gnx("server_id" to "gone", "kind" to "gnx.alert.space")).destination)
        assertEquals(AlertTap(null, null, null), tap(null, title = null))
    }
}

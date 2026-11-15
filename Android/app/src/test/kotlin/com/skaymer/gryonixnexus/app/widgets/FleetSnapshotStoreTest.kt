package com.skaymer.gryonixnexus.app.widgets

import java.nio.file.Files
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FleetSnapshotStoreTest {
    private fun store() = FleetSnapshotStore(Files.createTempDirectory("snapshot").resolve("fleet.json").toFile())

    @Test
    fun `a server is added once and keeps its other readings`() {
        val store = store()
        assertNull(store.read())
        store.updateServer("a", "orion") { it.copy(services = FleetSnapshot.ServicesSummary(5, 1, 10)) }
        store.updateServer("a", "orion 2") { it.copy(updates = FleetSnapshot.UpdatesSummary(2, 5, null, 11)) }
        val server = store.read()!!.servers.single()
        assertEquals("orion 2", server.name)
        assertEquals(1, server.services?.needingAttention)
        assertEquals(2, server.updates?.waiting)
    }

    @Test
    fun `protocols replace their own reading and a failure is kept`() {
        val store = store()
        store.upsertProtocol("a", "orion", FleetSnapshot.ProtocolDevices("wireguard-vpn", 2), null)
        store.upsertProtocol("a", "orion", FleetSnapshot.ProtocolDevices("amnezia-wg", 1), null)
        store.upsertProtocol("a", "orion", FleetSnapshot.ProtocolDevices("wireguard-vpn", 3), null)
        store.upsertProtocol("a", "orion", null, "timed out")
        val snapshot = store.read()!!
        assertEquals(4, snapshot.deviceCount)
        assertEquals("timed out", snapshot.servers.single().failure)
        assertEquals(1, snapshot.unreachableServerCount)
    }

    @Test
    fun `forgetting a server and writing the tunnel leave the rest`() {
        val store = store()
        store.updateServer("a", "orion") { it }
        store.updateServer("b", "draco") { it }
        store.writeTunnel(TunnelSnapshot(state = TunnelSnapshot.State.CONNECTED, profileCount = 1))
        assertTrue(store.forgetServer("a"))
        val snapshot = store.read()!!
        assertEquals(listOf("b"), snapshot.servers.map { it.id })
        assertTrue(snapshot.tunnel.isActive)
    }

    @Test
    fun `verdicts follow the readings`() {
        val well = FleetSnapshot(servers = listOf(FleetSnapshot.Server("a", "orion", services = FleetSnapshot.ServicesSummary(3, 0, 1))))
        assertEquals(WidgetPresentation.Verdict.WELL, WidgetPresentation.fleet(well))
        assertEquals(WidgetPresentation.Verdict.UNKNOWN, WidgetPresentation.fleet(FleetSnapshot()))
        assertEquals(WidgetPresentation.Verdict.ATTENTION, WidgetPresentation.updates(FleetSnapshot.UpdatesSummary(1, 3, null, 1)))
        assertEquals("1:02:03", TunnelClock.text(0, 3_723_000))
        assertEquals("—", WidgetPresentation.percent(null))
    }

    @Test
    fun `a summary push fills the readings and keeps the rest`() {
        val data = kotlinx.serialization.json.Json.parseToJsonElement(
            """{"kind":"gnx.widgets","server_id":"s","at":100,"services":{"total":9,"attention":1},""" +
                """"backups":{"on":true,"every_days":1,"services":3,"retention":7},""" +
                """"metrics":{"cpu":12.5,"mem_used":1,"mem_total":4,"disk_used":5,"disk_total":10}}""",
        ) as kotlinx.serialization.json.JsonObject
        val before = FleetSnapshot.Server("a", "orion", updates = FleetSnapshot.UpdatesSummary(2, 5, null, 1))
        val after = WidgetPush.apply(before, data, 100_000)
        assertEquals(1, after.services?.needingAttention)
        assertEquals(1, after.backups?.everyDays)
        assertEquals(50.0, after.metrics?.diskPercent)
        assertNull(after.security)
        assertEquals(2, after.updates?.waiting, "a push without updates keeps the app's reading")
    }
}

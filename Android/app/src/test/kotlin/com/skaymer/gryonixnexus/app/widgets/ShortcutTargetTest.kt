package com.skaymer.gryonixnexus.app.widgets

import com.skaymer.gryonixnexus.app.shell.AppTab
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ShortcutTargetTest {
    private val servers = listOf("a", "b", "c", "d", "e").map { FleetSnapshot.Server(id = it, name = it.uppercase()) }

    @Test
    fun aTabExtraOpensThatTab() {
        assertEquals(ShortcutTarget.Tab(AppTab.VPN), ShortcutTarget.of(ShortcutTarget.ACTION, "vpn", null))
    }

    @Test
    fun aServerExtraWinsOverATab() {
        assertEquals(ShortcutTarget.Server("b"), ShortcutTarget.of(ShortcutTarget.ACTION, "vpn", "b"))
    }

    @Test
    fun otherActionsAndUnknownTabsOpenNothing() {
        assertNull(ShortcutTarget.of("android.intent.action.MAIN", "vpn", null))
        assertNull(ShortcutTarget.of(ShortcutTarget.ACTION, "nonsense", null))
        assertNull(ShortcutTarget.of(ShortcutTarget.ACTION, null, " "))
    }

    @Test
    fun recentServersComeFirstThenTheRestUpToTheLimit() {
        val chosen = ShortcutPlan.servers(listOf("c", "gone", "a"), servers)
        assertEquals(listOf("c", "a", "b", "d"), chosen.map { it.id })
    }

    @Test
    fun rememberingMovesTheServerToTheFrontWithoutDuplicates() {
        assertEquals(listOf("b", "a", "c"), ShortcutPlan.remember(listOf("a", "b", "c"), "b"))
        assertEquals(listOf("e", "a", "b", "c"), ShortcutPlan.remember(listOf("a", "b", "c", "d"), "e"))
    }

    @Test
    fun theTileIsLitOnlyWhenEveryServiceIsWell() {
        val well = FleetSnapshot(servers = listOf(servers[0].copy(services = FleetSnapshot.ServicesSummary(3, 0, 1))))
        val sick = FleetSnapshot(servers = listOf(servers[0].copy(services = FleetSnapshot.ServicesSummary(3, 2, 1))))
        assertTrue(ServerTileModel.of(well).active)
        assertFalse(ServerTileModel.of(sick).active)
        assertEquals(2, ServerTileModel.of(sick).attention)
        assertFalse(ServerTileModel.of(null).hasReadings)
    }
}

package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.app.shell.TabBarSettings
import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** What the server screen folds by itself */
class ServiceGroupingRuleTests {
    @Test
    fun `grouping turns itself on when a shelf holds two`() {
        assertTrue(ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.NEXTCLOUD, ServiceID.SEAFILE)))
        assertTrue(ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.IMMICH, ServiceID.PHOTOPRISM)))
        assertTrue(
            ServiceGrouping.aShelfHoldsSeveral(
                listOf(ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG, ServiceID.SHADOWSOCKS)
            )
        )
    }

    @Test
    fun `grouping stays off while every service is alone on its shelf`() {
        assertFalse(ServiceGrouping.aShelfHoldsSeveral(emptyList()))
        assertFalse(ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.NEXTCLOUD)))
        assertFalse(
            ServiceGrouping.aShelfHoldsSeveral(
                listOf(ServiceID.NEXTCLOUD, ServiceID.IMMICH, ServiceID.JELLYFIN)
            )
        )
    }

    @Test
    fun `a service that arrived alongside another still counts as a row`() {
        assertTrue(
            ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.WIREGUARD_VPN, ServiceID.VPN_PANEL)),
            "the panel is drawn under VPN with the protocol, so that group holds two"
        )
        assertTrue(
            ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.HEADSCALE, ServiceID.TAILSCALE_NODE))
        )
    }

    @Test
    fun `the implicit category is counted where it is drawn`() {
        assertFalse(
            ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.VPN_PANEL, ServiceID.NEXTCLOUD)),
            "one VPN row and one files row is two groups of one"
        )
    }

    @Test
    fun `crafty controller is counted under games, not vpn`() {
        assertTrue(
            ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.MINECRAFT_JAVA, ServiceID.CRAFTY_CONTROLLER)),
            "the panel is drawn under Game servers with Minecraft, so that group holds two"
        )
        assertFalse(
            ServiceGrouping.aShelfHoldsSeveral(listOf(ServiceID.VPN_PANEL, ServiceID.CRAFTY_CONTROLLER)),
            "one VPN row and one game-servers row is two groups of one, not one group of two"
        )
    }

    @Test
    fun `an explicit choice overrules the servers own answer`() {
        val tabs = TabBarSettings(InMemorySettingsStore())
        assertNull(tabs.groupServicesOverride.value)
        assertTrue(tabs.groupsServices(listOf(ServiceID.NEXTCLOUD, ServiceID.SEAFILE)))
        assertFalse(tabs.groupsServices(listOf(ServiceID.NEXTCLOUD)))

        tabs.setGroupServicesOverride(false)
        assertFalse(
            tabs.groupsServices(listOf(ServiceID.NEXTCLOUD, ServiceID.SEAFILE)),
            "an owner who switched grouping off means every server"
        )

        tabs.setGroupServicesOverride(true)
        assertTrue(
            tabs.groupsServices(listOf(ServiceID.NEXTCLOUD)),
            "and one who switched it on means every server too"
        )

        tabs.setGroupServicesOverride(null)
        assertFalse(
            tabs.groupsServices(listOf(ServiceID.NEXTCLOUD)),
            "clearing it has to give the server its say back"
        )
    }

    @Test
    fun `an explicit off is remembered as off and not as unset`() {
        val store = InMemorySettingsStore()
        val first = TabBarSettings(store)

        first.setGroupServicesOverride(false)
        assertEquals(false, TabBarSettings(store).groupServicesOverride.value)

        first.setGroupServicesOverride(null)
        assertNull(TabBarSettings(store).groupServicesOverride.value)
    }
}

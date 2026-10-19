package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.ModSlot
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentModOperationsTests` */
class AgentModOperationsTest {
    @Test
    fun `vanilla has no loader and every other type does`() {
        assertNull(AgentModOperations.loader("VANILLA"))
        assertNull(AgentModOperations.loader(""))
        assertEquals("fabric", AgentModOperations.loader("FABRIC"))
        assertEquals("forge", AgentModOperations.loader("FORGE"))
        assertEquals("paper", AgentModOperations.loader("PAPER"))
        assertEquals("fabric", AgentModOperations.loader("fabric"))
    }

    @Test
    fun `the server type decides which directory an upload goes in`() {
        assertEquals(ModSlot.MOD_SLOT_PLUGINS, AgentModOperations.slot("PAPER"))
        assertEquals(ModSlot.MOD_SLOT_PLUGINS, AgentModOperations.slot("SPIGOT"))
        assertEquals(ModSlot.MOD_SLOT_MODS, AgentModOperations.slot("FABRIC"))
        assertEquals(ModSlot.MOD_SLOT_MODS, AgentModOperations.slot("FORGE"))
        assertEquals(ModSlot.MOD_SLOT_MODS, AgentModOperations.slot("SOMETHING_NEW"))
    }

    @Test
    fun `a picked mod is written pinned to its version`() {
        assertEquals("sodium:AANobbMO", AgentModOperations.entry("sodium", "AANobbMO"))
        assertEquals("sodium", AgentModOperations.entry("sodium", ""))
    }

    @Test
    fun `the setting round trips without empty entries`() {
        val entries = AgentModOperations.entries(" fabric-api:bQZpGIz0 , ,sodium:AANobbMO,")
        assertEquals(listOf("fabric-api:bQZpGIz0", "sodium:AANobbMO"), entries)
        assertEquals("fabric-api:bQZpGIz0,sodium:AANobbMO", AgentModOperations.setting(entries))
        assertEquals("", AgentModOperations.setting(listOf("", "  ")))
        assertEquals(emptyList(), AgentModOperations.entries(""))
    }

    @Test
    fun `the slug is read back out of an entry`() {
        assertEquals("sodium", AgentModOperations.slug("sodium:AANobbMO"))
        assertEquals("sodium", AgentModOperations.slug("sodium"))
    }

    @Test
    fun `only the java server is addressed`() {
        assertEquals(ServiceID.MINECRAFT_JAVA.rawValue, AgentModOperations.SERVICE_ID)
    }
}

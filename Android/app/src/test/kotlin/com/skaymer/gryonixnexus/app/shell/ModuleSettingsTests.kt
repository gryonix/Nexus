package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.app.servers.AddServiceViewModel
import com.skaymer.gryonixnexus.catalog.ServiceID
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ModuleSettingsTests {
    @Test
    fun `every module starts off, in the agreed order`() {
        val modules = ModuleSettings(InMemorySettingsStore())
        assertTrue(AppModule.entries.none { modules.isOn(it) })
        assertEquals(
            listOf("ai", "vpnAdvanced", "portForwarding", "scripts", "dockerAdvanced"),
            AppModule.entries.map { it.id },
        )
    }

    @Test
    fun `a toggle is remembered by a new instance and unknown ids stay on`() {
        val store = InMemorySettingsStore()
        ModuleSettings(store).set(AppModule.AI, true)
        val again = ModuleSettings(store)
        assertTrue(again.isOn("ai"))
        assertTrue(again.isOn("somethingNew"))
    }

    @Test
    fun `AirPlay is always on offer and an old audio value is ignored`() {
        val store = InMemorySettingsStore()
        store.setBoolean("modules.audio", false)
        assertTrue(AppModule.entries.none { it.id == "audio" })
        ModuleSettings(store)
        val offered = AddServiceViewModel
            .available(emptySet(), localOnly = false)
            .flatMap { it.second }.map { it.id }
        assertTrue(ServiceID.SHAIRPORT_SYNC in offered)
    }

    @Test
    fun `server sets decide when kept on servers`() {
        val modules = ModuleSettings(InMemorySettingsStore())
        assertTrue(modules.keptOnServers.value)
        modules.set(AppModule.DOCKER_ADVANCED, true, "a")
        modules.adopt("b", setOf("ai"))
        assertTrue(modules.isOn(AppModule.DOCKER_ADVANCED, "a"))
        assertTrue(!modules.isOn(AppModule.DOCKER_ADVANCED, "b"))
        assertTrue(modules.isOn(AppModule.AI))
        modules.forget("b")
        assertTrue(!modules.isOn(AppModule.AI))
    }

    @Test
    fun `a device that had modules on keeps them local and sets survive a restart`() {
        val store = InMemorySettingsStore()
        store.setBoolean(ModuleSettings.key(AppModule.AI), true)
        val local = ModuleSettings(store)
        assertTrue(!local.keptOnServers.value)
        assertTrue(local.isOn(AppModule.AI))
        local.setKeptOnServers(true)
        local.adopt("srv", setOf("scripts"))
        assertEquals(mapOf("srv" to setOf("scripts")), ModuleSettings(store).servers.value)
    }
}

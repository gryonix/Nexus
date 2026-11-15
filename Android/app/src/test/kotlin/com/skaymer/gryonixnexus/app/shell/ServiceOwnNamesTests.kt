package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ServiceOwnNamesTests {
    private val vaultwarden = assertNotNull(ServiceRegistry.service(ServiceID.VAULTWARDEN))

    @Test
    fun `a given name replaces the catalog one on that server only`() {
        val store = InMemorySettingsStore()
        val names = ServiceOwnNames(store)
        assertEquals(vaultwarden.displayName, names.title(vaultwarden, "a"))
        names.set("  Passwords ", vaultwarden.id.rawValue, "a", sent = true)
        assertEquals("Passwords", names.title(vaultwarden, "a"))
        assertEquals(vaultwarden.displayName, names.title(vaultwarden, "b"))
        assertEquals("Passwords", ServiceOwnNames(store).title(vaultwarden, "a"))
    }

    @Test
    fun `an empty name puts the catalog name back`() {
        val names = ServiceOwnNames(InMemorySettingsStore())
        names.set("Passwords", vaultwarden.id.rawValue, "a", sent = true)
        names.set("   ", vaultwarden.id.rawValue, "a", sent = true)
        assertTrue(names.names("a").isEmpty())
        assertTrue(names.servers.value.isEmpty())
    }

    @Test
    fun `a name the agent did not take waits until the server answers`() {
        val names = ServiceOwnNames(InMemorySettingsStore())
        names.set("Passwords", vaultwarden.id.rawValue, "a", sent = false)
        assertEquals(setOf("a"), names.unsent)
        names.adopt("a", mapOf(vaultwarden.id.rawValue to "Passwords"))
        assertTrue(names.unsent.isEmpty())
    }

    @Test
    fun `the server's set replaces the local one`() {
        val names = ServiceOwnNames(InMemorySettingsStore())
        names.set("Old", vaultwarden.id.rawValue, "a", sent = true)
        names.adopt("a", mapOf("nextcloud" to "Files", "seafile" to ""))
        assertEquals(mapOf("nextcloud" to "Files"), names.names("a"))
    }

    @Test
    fun `a name is one trimmed line of sixty characters`() {
        assertEquals("My vault", ServiceOwnNames.cleaned("  My\nvault  "))
        assertEquals(60, ServiceOwnNames.cleaned("я".repeat(80)).length)
    }
}

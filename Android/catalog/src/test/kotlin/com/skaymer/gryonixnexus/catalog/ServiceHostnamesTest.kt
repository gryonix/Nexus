package com.skaymer.gryonixnexus.catalog

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ServiceHostnamesTest {
    private fun context(settings: ServiceSettings = ServiceSettings()) =
        ServiceContext(domain = "example.com", sshUser = "server-user", settings = settings)

    @Test
    fun `every published service is accounted for`() {
        val context = context()
        for (service in ServiceRegistry.all.filter { it.webIngress(context) != null }) {
            val named = ServiceHostnames.settings[service.id] != null
            val fixed = service.id in ServiceHostnames.fixedHostnameServices
            assertTrue(
                named || fixed,
                "${service.id.rawValue} is published by Caddy but neither nameable nor listed as fixed",
            )
            assertFalse(
                named && fixed,
                "${service.id.rawValue} cannot be both nameable and fixed",
            )
        }
    }

    /** A row may not point at somebody else's field */
    @Test
    fun `each entry drives the service it names`() {
        for (id in ServiceHostnames.settings.keys) {
            val service = requireNotNull(ServiceRegistry.service(id)) {
                "${id.rawValue} is in the table but not in the catalog"
            }
            val settings = ServiceSettings().applyingHostnames(mapOf(id to "chosen.example.org"))
            assertEquals(
                "chosen.example.org",
                service.webIngress(context(settings))?.hostname,
                "${id.rawValue}'s table entry names the wrong field",
            )
        }
    }

    @Test
    fun `naming one service leaves the others on their defaults`() {
        val defaults = context()
        for (id in ServiceHostnames.settings.keys) {
            val changed = context(ServiceSettings().applyingHostnames(mapOf(id to "chosen.example.org")))
            for (other in ServiceHostnames.settings.keys.filter { it != id }) {
                val service = ServiceRegistry.service(other) ?: continue
                assertEquals(
                    service.webIngress(defaults)?.hostname,
                    service.webIngress(changed)?.hostname,
                    "naming ${id.rawValue} also moved ${other.rawValue}",
                )
            }
        }
    }

    @Test
    fun `values are cleaned the one way`() {
        val settings = ServiceSettings()
            .applyingHostnames(mapOf(ServiceID.SEAFILE to "  Files.Example.COM "))
        assertEquals("files.example.com", settings.seafileHostname)
    }

    @Test
    fun `blank names are not carried back`() {
        val settings = ServiceSettings().applyingHostnames(
            mapOf(ServiceID.SEAFILE to "files.example.com", ServiceID.PSONO to "   "),
        )
        assertEquals(mapOf(ServiceID.SEAFILE to "files.example.com"), settings.namedHostnames)
    }
}

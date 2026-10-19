package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ServiceContextWireTest {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private fun golden(): String =
        checkNotNull(javaClass.getResourceAsStream("/swift-service-context.json")) {
            "the Swift-dumped fixture is missing"
        }.bufferedReader().readText()

    @Test
    fun `the context Swift wrote decodes here`() {
        val context = json.decodeFromString<ServiceContext>(golden())
        assertEquals("example.com", context.domain)
        assertEquals(listOf("example.org"), context.additionalDomains)
        assertEquals("admin", context.sshUser)
        assertEquals(AppLanguage.RU, context.language)
        assertEquals(VPNClientAccess.BOTH, context.settings.vpnClientAccess)
        assertEquals(setOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD), context.installedServices)
        assertEquals(setOf(ServiceID.ADGUARD_HOME, ServiceID.PIHOLE,
                           ServiceID.HOMEPAGE, ServiceID.CRAFTY_CONTROLLER),
                     context.settings.autheliaProtectedServices)
        assertEquals("/opt/mailcow-dockerized", context.settings.mailcowPath)
        assertEquals(51822, context.settings.amneziaWGPort)
        assertEquals(false, context.settings.piholeServesNetwork)
    }

    @Test
    fun `re-encoding produces the same object Swift did`() {
        val context = json.decodeFromString<ServiceContext>(golden())
        val ours = json.encodeToJsonElement(context) as JsonObject
        val theirs = json.parseToJsonElement(golden()) as JsonObject
        assertEquals(theirs.keys.sorted(), ours.keys.sorted(),
                     "top-level keys differ — one app stores a field the other drops")
        val theirSettings = theirs["settings"] as JsonObject
        val ourSettings = ours["settings"] as JsonObject
        assertEquals(theirSettings.keys.sorted(), ourSettings.keys.sorted(),
                     "settings keys differ between the two apps")
        assertEquals(theirs, ours)
    }

    /** What an OLDER file looks like: most keys absent */
    @Test
    fun `an older file without the newer keys still loads`() {
        val minimal = """{"domain":"example.com","sshUser":"admin"}"""
        val context = json.decodeFromString<ServiceContext>(minimal)
        assertEquals(AppLanguage.EN, context.language)
        assertTrue(context.additionalDomains.isEmpty())
        assertTrue(context.installedServices.isEmpty())
        assertEquals(VPNClientAccess.BOTH, context.settings.vpnClientAccess)
        assertEquals("/opt/backups", context.settings.backupRoot)
    }

    @Test
    fun `a field from a newer app is ignored rather than fatal`() {
        val fromTheFuture =
            """{"domain":"example.com","sshUser":"admin","somethingAddedLater":42}"""
        assertEquals("example.com", json.decodeFromString<ServiceContext>(fromTheFuture).domain)
    }

    @Test
    fun `backup directories follow the shared root except where they were pinned`() {
        val context = json.decodeFromString<ServiceContext>(golden())
        assertEquals("/opt/backups/mailcow", context.backupDirectory(ServiceID.MAILCOW))
        assertEquals("/opt/backups/vaultwarden", context.backupDirectory(ServiceID.VAULTWARDEN))
        assertEquals("/opt/backups/nextcloud", context.backupDirectory(ServiceID.NEXTCLOUD))
    }

    @Test
    fun `a web hostname is mirrored onto every additional domain`() {
        val context = json.decodeFromString<ServiceContext>(golden())
        assertEquals(listOf("cloud.example.org"), context.mirroredHostnames("cloud.example.com"))
        assertEquals(listOf("cloud.example.com", "cloud.example.org"),
                     context.servedHostnames("cloud.example.com"))
        assertTrue(context.mirroredHostnames("cloud.elsewhere.net").isEmpty())
    }
}

package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AccessStoreTests {
    private val secrets = InMemorySecretStore()

    private fun reports(id: String = "S-1") = InstallReportStore(secrets, id, clock = { 42L })

    private fun credentials(id: String = "S-1") = AccessCredentialStore(secrets, id)

    @Test
    fun `a saved report reads back`() {
        reports().save("single", "Nextcloud: https://cloud.example.test")
        assertEquals(
            listOf(StoredInstallReport("single", "Nextcloud: https://cloud.example.test", 42L)),
            reports().load()
        )
    }

    /** Scenario B prints TWO reports, minutes apart */
    @Test
    fun `saving one machine keeps the other`() {
        reports().save("vps", "relay")
        reports().save("home", "home box")
        assertEquals(listOf("vps", "home"), reports().load().map { it.host })
    }

    @Test
    fun `a second report for the same machine replaces the first`() {
        reports().save("vps", "old")
        reports().save("vps", "new")
        assertEquals(listOf("new"), reports().load().map { it.text })
    }

    @Test
    fun `reports of another deployment are not read`() {
        reports("S-1").save("single", "first")
        assertTrue(reports("S-2").load().isEmpty())
    }

    @Test
    fun `the items are named the way the other app names them`() {
        reports("A-1").save("single", "text")
        credentials("A-1").save(mapOf("single|Nextcloud" to AccessCredential(password = "x")))
        assertTrue(secrets.items.containsKey("install-report-A-1"))
        assertTrue(secrets.items.containsKey("access-credentials-A-1"))
    }

    @Test
    fun `unreadable storage answers empty rather than guessing`() {
        secrets.setString("install-report-S-1", "{ this is not the report }")
        secrets.setString("access-credentials-S-1", "]]")
        assertTrue(reports().load().isEmpty())
        assertTrue(credentials().load().isEmpty())
    }

    @Test
    fun `an override reads back under the key that carries its host`() {
        val key = AccessCredentialStore.key("vps", "Nextcloud")
        credentials().save(mapOf(key to AccessCredential(login = "me", password = "pw")))
        assertEquals(AccessCredential(login = "me", password = "pw"), credentials().load()[key])
    }

    /** An empty override set DELETES the item */
    @Test
    fun `clearing every override removes the stored item`() {
        credentials().save(mapOf("vps|Nextcloud" to AccessCredential(password = "pw")))
        credentials().save(mapOf("vps|Nextcloud" to AccessCredential()))
        assertNull(secrets.items["access-credentials-S-1"])
        assertTrue(credentials().load().isEmpty())
    }

    @Test
    fun `an empty credential knows it is empty`() {
        assertTrue(AccessCredential().isEmpty)
        assertTrue(AccessCredential(login = "").isEmpty)
        assertFalse(AccessCredential(token = "t").isEmpty)
    }
}

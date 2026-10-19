package com.skaymer.gryonixnexus.app.access

import gryonixnexusd.v1.VaultEntry
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AccessVaultTest {
    private fun card(
        title: String = "Vaultwarden",
        login: String = "admin@example.com",
        password: String = "from-the-report",
        token: String = "",
        host: String = "single",
    ) = AccessAccount(
        host = host,
        title = title,
        website = "https://vault.example.com",
        reportLogin = login,
        reportPassword = password,
        reportToken = token,
        login = login,
        password = password,
        token = token,
        hasToken = token.isNotEmpty(),
        isVaultwarden = true,
    ).markingLoaded()

    private fun remote(
        id: String = "single|Vaultwarden",
        password: String,
        at: Long,
        by: String = "phone-b",
        deleted: Boolean = false,
    ) = VaultEntry(
        id = id,
        host = "single",
        title = "Vaultwarden",
        website = "https://vault.example.com",
        login = "admin@example.com",
        password = password,
        updated_at = at,
        updated_by = by,
        deleted = deleted,
    )

    // --------------------------------------------------- What a Save sends

    /** Both kinds go, and the timestamp is the difference */
    @Test
    fun `a save sends both the edits and the untouched report values`() {
        val edited = card(title = "Nextcloud").copy(password = "changed-just-now")
        val untouched = card()
        val out = AccessVault.entriesToPush(listOf(edited, untouched), 1_700_000_000, "phone-a")

        assertEquals(2, out.size)
        val byPassword = out.associateBy { it.password }
        assertEquals(1_700_000_000L, byPassword["changed-just-now"]?.updated_at)
        assertEquals("phone-a", byPassword["changed-just-now"]?.updated_by)
        assertEquals(0L, byPassword["from-the-report"]?.updated_at)
        assertEquals("agent", byPassword["from-the-report"]?.updated_by)
    }

    @Test
    fun `an account with no credential is not sent`() {
        val blank = card(login = "", password = "", token = "")
        assertTrue(AccessVault.entriesToPush(listOf(blank), 1, "phone-a").isEmpty())
    }

    // ------------------------------------------------- What the server says

    @Test
    fun `a newer server value replaces what the report gave`() {
        val out = AccessVault.applying(
            listOf(remote(password = "changed-on-the-other-phone", at = 200)),
            listOf(card()),
        )
        assertEquals("changed-on-the-other-phone", out.single().password)
    }

    @Test
    fun `a value taken from the server is not then reported as an edit`() {
        val out = AccessVault.applying(
            listOf(remote(password = "changed-on-the-other-phone", at = 200)),
            listOf(card()),
        )
        assertTrue(!out.single().isChanged)
    }

    @Test
    fun `an account the server alone knows becomes a card`() {
        val out = AccessVault.applying(
            listOf(remote(id = "single|AdGuard Home", password = "hunter2", at = 100)),
            emptyList(),
        )
        assertEquals(1, out.size)
        assertEquals("hunter2", out.single().password)
        assertEquals("", out.single().reportPassword)
    }

    /** A deletion elsewhere removes the row here */
    @Test
    fun `an account deleted elsewhere leaves the screen`() {
        val out = AccessVault.applying(
            listOf(remote(password = "", at = 200, deleted = true)),
            listOf(card()),
        )
        assertTrue(out.isEmpty())
    }

    /** An older server value loses to what this device holds */
    @Test
    fun `an older server value does not overwrite a newer local edit`() {
        val edited = card().copy(password = "typed-here", updatedAt = 300, updatedBy = "phone-a")
        val out = AccessVault.applying(listOf(remote(password = "stale", at = 100)), listOf(edited))
        assertEquals("typed-here", out.single().password)
    }

    @Test
    fun `an untouched card loses to anything the server holds`() {
        val out = AccessVault.applying(listOf(remote(password = "from-the-server", at = 1)), listOf(card()))
        assertEquals("from-the-server", out.single().password)
    }

    @Test
    fun `a token from the server adds the field`() {
        val withToken = remote(password = "p", at = 200).copy(token = "admin-token")
        val out = AccessVault.applying(listOf(withToken), listOf(card()))
        assertTrue(out.single().hasToken)
        assertEquals("admin-token", out.single().token)
    }

    @Test
    fun `nothing from the server leaves the cards as they were`() {
        val out = AccessVault.applying(emptyList(), listOf(card()))
        assertEquals("from-the-report", out.single().password)
        assertEquals("https://vault.example.com", out.single().website)
        assertTrue(!out.single().isChanged)
    }
}

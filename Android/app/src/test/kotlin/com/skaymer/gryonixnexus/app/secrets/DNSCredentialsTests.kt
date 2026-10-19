package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class DNSCredentialsTests {
    private fun store(): Triple<DNSCredentials, InMemorySettingsStore, InMemorySecretStore> {
        val settings = InMemorySettingsStore()
        val secrets = InMemorySecretStore()
        return Triple(DNSCredentials(settings, secrets), settings, secrets)
    }

    // ------------------------------------------- Nothing moves in the keystore

    @Test
    fun `the original Cloudflare account keeps its own item names`() {
        assertEquals(
            "cloudflare-api-token",
            DNSCredentials.tokenKey(DNSCredentials.CLOUDFLARE_FIRST_ID, DNSProviderKind.CLOUDFLARE),
        )
        assertEquals(
            "cloudflare-tunnel-api-token",
            DNSCredentials.tunnelKey(DNSCredentials.CLOUDFLARE_FIRST_ID),
        )
    }

    @Test
    fun `a later Cloudflare account keeps its suffixed item names`() {
        assertEquals(
            "cloudflare-api-token.ABC",
            DNSCredentials.tokenKey("ABC", DNSProviderKind.CLOUDFLARE),
        )
        assertEquals("cloudflare-tunnel-api-token.ABC", DNSCredentials.tunnelKey("ABC"))
    }

    @Test
    fun `a credential adopted from the per-kind store reads that store's key`() {
        for (kind in DNSProviderKind.entries) {
            if (kind == DNSProviderKind.CLOUDFLARE) continue
            assertEquals(
                "dns-provider-token.${kind.name}",
                DNSCredentials.tokenKey(DNSCredentials.adoptedID(kind), kind),
                "${kind.displayName} would lose the token this device already has",
            )
        }
    }

    /** Anything added from here on gets a key of its own — so a SECOND
     * Hetzner token cannot land on top of the first. */
    @Test
    fun `a second token for a provider gets a key of its own`() {
        val first = DNSCredentials.tokenKey(
            DNSCredentials.adoptedID(DNSProviderKind.HETZNER), DNSProviderKind.HETZNER
        )
        val second = DNSCredentials.tokenKey("9E2F", DNSProviderKind.HETZNER)
        assertTrue(first != second)
        assertEquals("dns-credential-token.9E2F", second)
    }

    // ------------------------------------------------------------------- List

    @Test
    fun `a fresh device lists nothing at all`() {
        val (credentials, _, _) = store()
        assertTrue(credentials.all.isEmpty())
        assertNull(credentials.selectedID)
        assertNull(credentials.selected)
    }

    @Test
    fun `an added credential carries its name and provider and is chosen`() {
        val (credentials, _, _) = store()
        val added = credentials.add("work", DNSProviderKind.HETZNER)
        assertEquals(listOf(added.id), credentials.all.map { it.id })
        assertEquals("work", credentials.all.first().name)
        assertEquals(DNSProviderKind.HETZNER, credentials.all.first().kind)
        assertEquals(added.id, credentials.selectedID)
    }

    @Test
    fun `an unnamed credential falls back to the provider's name`() {
        val (credentials, _, _) = store()
        val added = credentials.add("   ", DNSProviderKind.PORKBUN)
        assertEquals(DNSProviderKind.PORKBUN.displayName, credentials.credential(added.id).name)
        assertNull(credentials.storedName(added.id))
    }

    @Test
    fun `deleting the chosen credential moves the choice`() {
        val (credentials, _, _) = store()
        val first = credentials.add("one", DNSProviderKind.CLOUDFLARE)
        val second = credentials.add("two", DNSProviderKind.DIGITALOCEAN)
        credentials.selectedID = second.id

        credentials.remove(second.id)
        assertEquals(listOf(first.id), credentials.all.map { it.id })
        assertEquals(first.id, credentials.selectedID)
    }

    // --------------------------------------------------- What an upgrade finds

    @Test
    fun `a stored Cloudflare account list comes across wholly`() {
        val (credentials, settings, _) = store()
        settings.setStringList(
            DNSCredentials.LEGACY_CLOUDFLARE_IDS,
            listOf(DNSCredentials.CLOUDFLARE_FIRST_ID, "SECOND"),
        )
        settings.setString(DNSCredentials.LEGACY_CLOUDFLARE_NAME_PREFIX + "SECOND", "work")
        settings.setString(DNSCredentials.LEGACY_CLOUDFLARE_SELECTED, "SECOND")

        credentials.adoptStoredTokensIfNeeded()

        assertEquals(
            listOf(DNSCredentials.CLOUDFLARE_FIRST_ID, "SECOND"),
            credentials.all.map { it.id },
        )
        assertTrue(credentials.all.all { it.kind == DNSProviderKind.CLOUDFLARE })
        assertEquals("work", credentials.credential("SECOND").name)
        assertEquals("SECOND", credentials.selectedID)
    }

    @Test
    fun `adopting does nothing once a list exists`() {
        val (credentials, settings, _) = store()
        settings.setStringList(
            DNSCredentials.LEGACY_CLOUDFLARE_IDS,
            listOf(DNSCredentials.CLOUDFLARE_FIRST_ID),
        )
        credentials.adoptStoredTokensIfNeeded()
        credentials.remove(DNSCredentials.CLOUDFLARE_FIRST_ID)

        credentials.adoptStoredTokensIfNeeded()
        assertTrue(
            credentials.all.isEmpty(),
            "a deleted credential came back — the old keys are being read every launch",
        )
    }

    @Test
    fun `a token from the per-kind store becomes a row named after its provider`() {
        val (credentials, _, secrets) = store()
        secrets.setString("dns-provider-token.${DNSProviderKind.HETZNER.name}", "token-for-the-test")

        credentials.adoptStoredTokensIfNeeded()

        val adopted = DNSCredentials.adoptedID(DNSProviderKind.HETZNER)
        assertEquals(listOf(adopted), credentials.all.map { it.id })
        assertEquals(DNSProviderKind.HETZNER, credentials.credential(adopted).kind)
        assertEquals(
            "token-for-the-test",
            DNSCredentialTokenStore(secrets).token(credentials.credential(adopted)),
            "the adopted row points at a key the token is not in",
        )
    }

    @Test
    fun `a device with no tokens anywhere adopts nothing`() {
        val (credentials, _, _) = store()
        credentials.adoptStoredTokensIfNeeded()
        assertTrue(credentials.all.isEmpty())
    }

    @Test
    fun `changing the provider moves the token to the new provider's key`() {
        val (credentials, _, secrets) = store()
        val tokens = DNSCredentialTokenStore(secrets)
        val credential = credentials.add("moved", DNSProviderKind.CLOUDFLARE)
        tokens.setToken(credential, "a-token")
        assertEquals("a-token", secrets.string(DNSCredentials.tokenKey(credential.id, DNSProviderKind.CLOUDFLARE)))

        tokens.move(credential, DNSProviderKind.HETZNER)
        credentials.update(credential.id, "moved", DNSProviderKind.HETZNER)

        val moved = credentials.credential(credential.id)
        assertEquals(DNSProviderKind.HETZNER, moved.kind)
        assertEquals("a-token", tokens.token(moved))
        assertNull(
            secrets.string(DNSCredentials.tokenKey(credential.id, DNSProviderKind.CLOUDFLARE)),
            "the token was left behind in the item the old provider read",
        )
    }

    /**
     * And the same for a credential ADOPTED from the per-kind store, whose
     * key carries the provider in its own name.
     */
    @Test
    fun `changing the provider of an adopted credential moves it off that store's key`() {
        val (credentials, _, secrets) = store()
        val tokens = DNSCredentialTokenStore(secrets)
        val legacyKey = "dns-provider-token.${DNSProviderKind.HETZNER.name}"
        secrets.setString(legacyKey, "a-token")
        credentials.adoptStoredTokensIfNeeded()
        val adopted = credentials.credential(DNSCredentials.adoptedID(DNSProviderKind.HETZNER))

        tokens.move(adopted, DNSProviderKind.PORKBUN)
        credentials.update(adopted.id, adopted.name, DNSProviderKind.PORKBUN)

        assertEquals("a-token", tokens.token(credentials.credential(adopted.id)))
        assertNull(secrets.string(legacyKey))
    }
}

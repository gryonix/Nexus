package com.skaymer.gryonixnexus.app.secrets

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class AppIdentitiesTests {
    @Test
    fun `the same server gets the same key every time`() {
        val identities = AppIdentities(InMemorySecretStore())
        assertEquals(identities.publicKey("server-a"), identities.publicKey("server-a"))
    }

    /** Per DEPLOYMENT, not per app */
    @Test
    fun `two servers get two keys`() {
        val identities = AppIdentities(InMemorySecretStore())
        assertNotEquals(identities.publicKey("server-a"), identities.publicKey("server-b"))
    }

    @Test
    fun `regenerating replaces the key`() {
        val store = InMemorySecretStore()
        val identities = AppIdentities(store)
        val before = identities.publicKey("server-a")
        val after = identities.regenerate("server-a").publicKeyOpenSSH
        assertNotEquals(before, after)
        assertEquals(after, identities.publicKey("server-a"))
    }

    @Test
    fun `regenerating one server leaves the others alone`() {
        val identities = AppIdentities(InMemorySecretStore())
        val other = identities.publicKey("server-b")
        identities.regenerate("server-a")
        assertEquals(other, identities.publicKey("server-b"))
    }

    @Test
    fun `forgetting the seed leaves nothing stored`() {
        val store = InMemorySecretStore()
        val secrets = DeploymentSecrets(store, "server-a")
        AppIdentities(store).publicKey("server-a")
        assertNotNull(secrets.identitySeed())
        secrets.forgetIdentitySeed()
        assertNull(secrets.identitySeed())
    }
}

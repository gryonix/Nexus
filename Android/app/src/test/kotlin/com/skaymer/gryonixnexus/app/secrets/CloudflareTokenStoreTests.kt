package com.skaymer.gryonixnexus.app.secrets

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CloudflareTokenStoreTests {
    private fun store() = CloudflareTokenStore(InMemorySecretStore())

    @Test
    fun `nothing is stored to begin with`() {
        val tokens = store()
        assertNull(tokens.dnsToken)
        assertNull(tokens.tunnelToken)
        assertFalse(tokens.canIssueTunnelToken)
    }

    /** The two are separate items, not one with more rights */
    @Test
    fun `the DNS token and the tunnel token do not stand in for each other`() {
        val tokens = store()
        tokens.dnsToken = "zone-scoped"
        assertNull(tokens.tunnelToken)
        assertFalse(tokens.canIssueTunnelToken)

        tokens.tunnelToken = "account-scoped"
        assertEquals("zone-scoped", tokens.dnsToken)
        assertEquals("account-scoped", tokens.tunnelToken)
        assertTrue(tokens.canIssueTunnelToken)
    }

    /** An empty item is the same as no item */
    @Test
    fun `a blank token is no token`() {
        val tokens = store()
        tokens.tunnelToken = "   "
        assertNull(tokens.tunnelToken)
        assertFalse(tokens.canIssueTunnelToken)
    }

    /** Clearing is how somebody takes the app's access away again */
    @Test
    fun `clearing removes the token`() {
        val tokens = store()
        tokens.tunnelToken = "account-scoped"
        tokens.tunnelToken = null
        assertNull(tokens.tunnelToken)
        assertFalse(tokens.canIssueTunnelToken)
    }

    @Test
    fun `a pasted token keeps no surrounding whitespace`() {
        val tokens = store()
        tokens.dnsToken = "  abc123\n"
        assertEquals("abc123", tokens.dnsToken)
    }
}

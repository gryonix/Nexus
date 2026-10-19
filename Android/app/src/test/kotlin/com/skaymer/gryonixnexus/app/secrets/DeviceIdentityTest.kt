package com.skaymer.gryonixnexus.app.secrets

import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `DeviceIdentity` */
class DeviceIdentityTest {
    private class MemoryStore : SecretStore {
        val items = mutableMapOf<String, ByteArray>()
        var writes = 0
        override fun secret(account: String): ByteArray? = items[account]
        override fun setSecret(account: String, value: ByteArray) {
            writes += 1
            items[account] = value
        }
        override fun deleteSecret(account: String) { items.remove(account) }
    }

    /** A store that cannot answer — a keystore the platform refuses */
    private class BrokenStore : SecretStore {
        override fun secret(account: String): ByteArray? = throw IllegalStateException("keystore")
        override fun setSecret(account: String, value: ByteArray) = throw IllegalStateException("keystore")
        override fun deleteSecret(account: String) = throw IllegalStateException("keystore")
    }

    @Test
    fun `an id is minted on first use and kept`() {
        val store = MemoryStore()
        val minted = DeviceIdentity(store).uid
        assertTrue(minted.isNotEmpty())
        assertEquals(minted, store.string(DeviceIdentity.ACCOUNT))
    }

    /** The one that matters most */
    @Test
    fun `a second launch answers the same id`() {
        val store = MemoryStore()
        val first = DeviceIdentity(store).uid
        val second = DeviceIdentity(store).uid
        assertEquals(first, second)
        assertEquals(1, store.writes, "the id was re-minted rather than read back")
    }

    @Test
    fun `repeated reads do not touch the store again`() {
        val store = MemoryStore()
        val identity = DeviceIdentity(store)
        repeat(5) { identity.uid }
        assertEquals(1, store.writes)
    }

    @Test
    fun `a store that refuses gives an empty id rather than a new one`() {
        val identity = DeviceIdentity(BrokenStore())
        assertEquals("", identity.uid)
        assertEquals("", identity.uid)
    }

    @Test
    fun `forgetting mints a different id next time`() {
        val store = MemoryStore()
        val identity = DeviceIdentity(store)
        val first = identity.uid
        identity.forget()
        assertNotEquals(first, identity.uid)
    }

    @Test
    fun `the account name is the one the other app uses`() {
        assertEquals("device-uid", DeviceIdentity.ACCOUNT)
    }
}

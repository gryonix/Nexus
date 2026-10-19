package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class BackupNowChoiceTest {
    private val defaultsOn = setOf("vaultwarden", "mailcow")
    private val always = setOf("vaultwarden")

    @Test
    fun servicesAreTickedAndUntickedInOrder() {
        val choice = BackupNowChoice().toggled("nextcloud").toggled("mailcow").toggled("immich").toggled("mailcow")
        assertEquals(listOf("nextcloud", "immich"), choice.services)
    }

    @Test
    fun encryptionFollowsTheChosenServicesUntilSet() {
        val choice = BackupNowChoice(services = listOf("nextcloud"))
        assertFalse(choice.encrypting(defaultsOn))
        assertTrue(choice.toggled("mailcow").encrypting(defaultsOn))
        assertFalse(choice.toggled("mailcow").copy(encrypt = false).encrypting(defaultsOn))
    }

    @Test
    fun anAlwaysEncryptedServiceNeedsAKeyEvenWithEncryptionOff() {
        val choice = BackupNowChoice(services = listOf("nextcloud", "vaultwarden"), encrypt = false)
        assertFalse(choice.encrypts("nextcloud", defaultsOn, always))
        assertTrue(choice.encrypts("vaultwarden", defaultsOn, always))
        assertTrue(choice.needsKey(defaultsOn, always))
        assertFalse(BackupNowChoice(services = listOf("nextcloud"), encrypt = false).needsKey(defaultsOn, always))
    }

    @Test
    fun theStoredKeySendsNoPassword() {
        val choice = BackupNowChoice(services = listOf("mailcow"), passphrase = "typed-but-unused")
        assertNull(choice.passphraseToSend)
        assertEquals("typed-but-unused", choice.copy(key = BackupNowChoice.Key.TYPED).passphraseToSend)
    }

    @Test
    fun readiness() {
        assertFalse(BackupNowChoice().isReady(defaultsOn, always, true))
        val stored = BackupNowChoice(services = listOf("mailcow"))
        assertTrue(stored.isReady(defaultsOn, always, true))
        assertTrue(stored.isReady(defaultsOn, always, null))
        assertFalse(stored.isReady(defaultsOn, always, false))
        val typed = stored.copy(key = BackupNowChoice.Key.TYPED, passphrase = "longenough", confirmation = "different!")
        assertFalse(typed.isReady(defaultsOn, always, false))
        assertTrue(typed.copy(confirmation = "longenough").isReady(defaultsOn, always, false))
        assertFalse(typed.copy(passphrase = "short", confirmation = "short").isReady(defaultsOn, always, false))
        assertTrue(BackupNowChoice(services = listOf("nextcloud"), encrypt = false).isReady(defaultsOn, always, false))
    }

    @Test
    fun sizesAddUpAgainstTheTightestFreeSpace() {
        assertNull(BackupNowChoice.total(emptyList()))
        assertEquals(
            BackupEstimate(40, 90),
            BackupNowChoice.total(listOf(BackupEstimate(10, 100), BackupEstimate(30, 90))),
        )
    }
}

package com.skaymer.gryonixnexus.app.servers

import org.junit.jupiter.api.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PendingRulesTests {
    @Test
    fun `a changed value waits and an untouched or equal one does not`() {
        assertTrue(PendingRules.waits("daily", "off"))
        assertFalse(PendingRules.waits("off", "off"))
        assertFalse(PendingRules.waits<String>(null, "off"))
    }

    @Test
    fun `an invalid value or running work keeps the bar down`() {
        assertFalse(PendingRules.waits("b", "a", valid = false))
        assertFalse(PendingRules.waits("b", "a", busy = true))
        assertTrue(PendingRules.waits("b", "a", valid = true, busy = false))
    }

    @Test
    fun `a host name waits only when it is valid and new`() {
        assertTrue(PendingRules.hostName("draco", "orion"))
        assertFalse(PendingRules.hostName("orion", "orion"))
        assertFalse(PendingRules.hostName("Not A Name", "orion"))
        assertFalse(PendingRules.hostName("", "orion"))
    }

    @Test
    fun `a backup schedule waits when changed or when a passphrase is typed`() {
        assertFalse(PendingRules.backupSchedule(canSave = true, changed = false, typedPassphrase = ""))
        assertTrue(PendingRules.backupSchedule(canSave = true, changed = true, typedPassphrase = ""))
        assertTrue(PendingRules.backupSchedule(canSave = true, changed = false, typedPassphrase = "secret"))
        assertFalse(PendingRules.backupSchedule(canSave = false, changed = true, typedPassphrase = "secret"))
    }
}

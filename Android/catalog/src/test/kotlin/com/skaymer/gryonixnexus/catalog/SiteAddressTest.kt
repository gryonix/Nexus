package com.skaymer.gryonixnexus.catalog

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SiteAddressTest {
    @Test
    fun onlyNamesDnsAcceptsPass() {
        assertTrue(SiteAddress.isValid("music.example.com"))
        assertTrue(SiteAddress.isValid("hifi.local"))
        for (bad in listOf("music", "music..example.com", "-a.example.com", "a b.example.com", "musik.ä.de", "a_b.example.com", "")) {
            assertFalse(SiteAddress.isValid(bad), bad)
        }
        assertEquals("music.example.com", SiteAddress.normalized("  Music.Example.COM \n"))
    }
}

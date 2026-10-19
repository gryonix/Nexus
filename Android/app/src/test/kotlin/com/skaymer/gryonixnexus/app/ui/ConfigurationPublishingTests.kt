package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.core.DNSRecord
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class ConfigurationPublishingTests {
    private val records = listOf(
        DNSRecord("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4"),
        DNSRecord("example.com", DNSRecord.RecordType.TXT, "v=spf1 mx -all"),
    )

    @Test
    fun `the name the app connects by is published`() {
        val entry = entryRecord("Example.com", "example.com", records)
        assertEquals("example.com", entry?.name)
        assertEquals(DNSRecord.RecordType.A, entry?.type)
        assertEquals("203.0.113.4", entry?.value)
    }

    @Test
    fun `an address host, another zone or a listed name adds nothing`() {
        assertNull(entryRecord("203.0.113.4", "example.com", records))
        assertNull(entryRecord("other.org", "example.com", records))
        assertNull(entryRecord("mail.example.com", "example.com", records))
    }
}

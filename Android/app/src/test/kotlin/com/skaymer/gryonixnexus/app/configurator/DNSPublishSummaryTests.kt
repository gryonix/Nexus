package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.core.DNSPublishOutcome
import com.skaymer.gryonixnexus.core.DNSRecord
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class DNSPublishSummaryTests {
    private fun record(name: String) =
        DNSRecord(name = name, type = DNSRecord.RecordType.A, value = "203.0.113.4")

    private fun outcome(name: String, result: DNSPublishOutcome.Result) =
        DNSPublishOutcome(record(name), result)

    @Test
    fun `counts created, updated and unchanged separately`() {
        val outcomes = listOf(
            outcome("a.example.com", DNSPublishOutcome.Result.Created),
            outcome("b.example.com", DNSPublishOutcome.Result.Created),
            outcome("c.example.com", DNSPublishOutcome.Result.Updated),
            outcome("d.example.com", DNSPublishOutcome.Result.Unchanged),
        )
        val result = DNSPublishSummary.summarize("example.com", outcomes)
        assertEquals(
            listOf("example.com: 2 added, 1 updated, 1 already correct."),
            result.lines,
        )
        assertFalse(result.failed)
    }

    @Test
    fun `a rejected record adds its own line and marks the zone failed`() {
        val outcomes = listOf(
            outcome("a.example.com", DNSPublishOutcome.Result.Created),
            outcome(
                "vpn.example.com",
                DNSPublishOutcome.Result.Failed("A record already exists"),
            ),
        )
        val result = DNSPublishSummary.summarize("example.com", outcomes)
        assertEquals(
            listOf(
                "example.com: 1 added, 0 updated, 0 already correct.",
                "vpn.example.com: A record already exists",
            ),
            result.lines,
        )
        assertTrue(result.failed)
    }

    @Test
    fun `an empty zone reports zero for every count and does not fail`() {
        val result = DNSPublishSummary.summarize("example.com", emptyList())
        assertEquals(listOf("example.com: 0 added, 0 updated, 0 already correct."), result.lines)
        assertFalse(result.failed)
    }
}

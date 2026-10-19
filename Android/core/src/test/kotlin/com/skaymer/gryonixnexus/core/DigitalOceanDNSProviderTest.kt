package com.skaymer.gryonixnexus.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `DigitalOceanDNSProviderTests` */
class DigitalOceanDNSProviderTest {
    private val base = "https://api.example.test/v2"

    private fun provider(responses: List<Pair<String, Int>>):
        Pair<DigitalOceanDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return DigitalOceanDNSProvider("test-token", client, base) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private val emptyRecords = """{"domain_records":[]}""" to 200

    // ------------------------------------------------------------- Auth

    @Test
    fun `the token goes up as a bearer`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, "{}" to 200))
        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )
        assertEquals("Bearer test-token", client.sent.first().headers["Authorization"])
    }

    @Test
    fun `verify token reads account and writes nothing`() = runTest {
        val (provider, client) = provider(listOf("""{"account":{"email":"owner@example.com"}}""" to 200))
        provider.verifyToken()
        assertEquals(listOf("GET"), client.sent.map { it.method })
        assertEquals("$base/account", client.sent.first().url)
    }

    @Test
    fun `an invalid token is reported plainly`() = runTest {
        val (provider, _) =
            provider(listOf("""{"id":"unauthorized","message":"Unable to authenticate"}""" to 401))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: DigitalOceanError) {
            assertEquals(DigitalOceanError.InvalidToken, error)
        }
    }

    // ------------------------------------------------------------ Writing

    @Test
    fun `a missing record is created with a relative name`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"domain_record":{}}""" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        val create = client.sent.last()
        assertEquals("POST", create.method)
        assertEquals("$base/domains/example.com/records", create.url)
        val body = assertNotNull(client.lastBody())
        assertEquals("A", body["type"]?.jsonPrimitive?.content)
        // Relative to the zone — DigitalOcean's own convention.
        assertEquals("mail", body["name"]?.jsonPrimitive?.content)
        assertEquals("203.0.113.4", body["data"]?.jsonPrimitive?.content)
    }

    @Test
    fun `an apex record is named at`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"domain_record":{}}""" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals("@", client.lastBody()?.get("name")?.jsonPrimitive?.content)
    }

    @Test
    fun `an MX target carries a trailing dot`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"domain_record":{}}""" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)),
            "example.com",
        )

        assertEquals("mail.example.com.", client.lastBody()?.get("data")?.jsonPrimitive?.content)
        assertEquals(10, client.lastBody()?.get("priority")?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `a changed record is updated in place`() = runTest {
        val existing =
            """{"domain_records":[{"id":42,"type":"A","name":"mail","data":"198.51.100.9"}]}"""
        val (provider, client) = provider(listOf(existing to 200, """{"domain_record":{}}""" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        assertEquals("PUT", client.sent.last().method)
        assertEquals("$base/domains/example.com/records/42", client.sent.last().url)
    }

    @Test
    fun `an identical record is left alone`() = runTest {
        val existing =
            """{"domain_records":[{"id":42,"type":"A","name":"mail","data":"203.0.113.4"}]}"""
        val (provider, client) = provider(listOf(existing to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(1, client.sent.size, "nothing may be written when nothing changed")
    }

    @Test
    fun `one rejected record does not abandon the rest`() = runTest {
        val (provider, _) = provider(
            listOf(
                emptyRecords,
                """{"id":"unprocessable_entity","message":"name already exists"}""" to 422,
                """{"domain_record":{}}""" to 200,
            ),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(
                record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4"),
                record("vpn.example.com", DNSRecord.RecordType.A, "203.0.113.5"),
            ),
            "example.com",
        )

        assertTrue(outcomes[0].result is DNSPublishOutcome.Result.Failed)
        assertEquals(DNSPublishOutcome.Result.Created, outcomes[1].result)
    }

    @Test
    fun `a missing domain is reported by name`() = runTest {
        val (provider, _) =
            provider(listOf("""{"id":"not_found","message":"domain not found"}""" to 404))
        try {
            provider.publishReportingOutcomes(
                listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
                "example.com",
            )
            fail("expected an error")
        } catch (error: DigitalOceanError) {
            assertEquals(DigitalOceanError.ZoneNotFound("example.com"), error)
        }
    }
}

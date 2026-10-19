package com.skaymer.gryonixnexus.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `GoDaddyDNSProviderTests` */
class GoDaddyDNSProviderTest {
    private val base = "https://api.example.test/v3/domains"

    private fun provider(responses: List<Pair<String, Int>>):
        Pair<GoDaddyDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return GoDaddyDNSProvider("test-token", client, base) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private val emptyItems = """{"items":[]}""" to 200

    // ------------------------------------------------------------- Auth

    @Test
    fun `the token goes up as a bearer`() = runTest {
        val (provider, client) = provider(listOf(emptyItems, "{}" to 200))
        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )
        assertEquals("Bearer test-token", client.sent.first().headers["Authorization"])
    }

    @Test
    fun `verify token reads the domain list and writes nothing`() = runTest {
        val (provider, client) = provider(listOf("""{"items":[]}""" to 200))
        provider.verifyToken()
        assertEquals(listOf("GET"), client.sent.map { it.method })
        assertEquals("$base/domain-names?limit=1", client.sent.first().url)
    }

    @Test
    fun `an invalid token is reported plainly`() = runTest {
        val (provider, _) =
            provider(listOf("""{"code":"INVALID_BODY","message":"Authentication failed"}""" to 401))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: GoDaddyError) {
            assertEquals(GoDaddyError.InvalidToken, error)
        }
    }

    // ------------------------------------------------------------ Writing

    @Test
    fun `a missing record is created with a relative name`() = runTest {
        val (provider, client) = provider(listOf(emptyItems, "{}" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        val create = client.sent.last()
        assertEquals("POST", create.method)
        assertEquals("$base/zones/example.com/dns-records", create.url)
        val body = assertNotNull(client.lastBody())
        assertEquals("A", body["type"]?.jsonPrimitive?.content)
        // Relative to the zone — GoDaddy's own convention.
        assertEquals("mail", body["name"]?.jsonPrimitive?.content)
        assertEquals("203.0.113.4", body["data"]?.jsonPrimitive?.content)
        assertEquals(3600, body["ttl"]?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `an apex record is named at`() = runTest {
        val (provider, client) = provider(listOf(emptyItems, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals("@", client.lastBody()?.get("name")?.jsonPrimitive?.content)
    }

    @Test
    fun `the lookup filters by type and name`() = runTest {
        val (provider, client) = provider(listOf(emptyItems, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        val lookup = client.sent.first()
        assertEquals("GET", lookup.method)
        assertEquals("$base/zones/example.com/dns-records?name=mail&type=A", lookup.url)
    }

    @Test
    fun `an MX target carries a trailing dot`() = runTest {
        val (provider, client) = provider(listOf(emptyItems, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)),
            "example.com",
        )

        assertEquals("mail.example.com.", client.lastBody()?.get("data")?.jsonPrimitive?.content)
        assertEquals(10, client.lastBody()?.get("priority")?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `an SRV record folds weight and port into data`() = runTest {
        val (provider, client) = provider(listOf(emptyItems, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(
                DNSRecord(
                    name = "_minecraft._tcp.example.com",
                    type = DNSRecord.RecordType.SRV,
                    value = "0 5 25565 mc.example.com",
                    srv = DNSRecord.SRVData(priority = 0, weight = 5, port = 25565, target = "mc.example.com"),
                ),
            ),
            "example.com",
        )

        val body = assertNotNull(client.lastBody())
        assertEquals("5 25565 mc.example.com.", body["data"]?.jsonPrimitive?.content)
        assertEquals(0, body["priority"]?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `a changed record is updated in place keeping the existing ttl`() = runTest {
        val existing =
            """{"items":[{"recordId":"rec_42","type":"A","name":"mail","data":"198.51.100.9","ttl":900}]}"""
        val (provider, client) = provider(listOf(existing to 200, "{}" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        val update = client.sent.last()
        assertEquals("PUT", update.method)
        assertEquals("$base/zones/example.com/dns-records/rec_42", update.url)
        assertEquals(900, client.lastBody()?.get("ttl")?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `an identical record is left alone`() = runTest {
        val existing =
            """{"items":[{"recordId":"rec_42","type":"A","name":"mail","data":"203.0.113.4","ttl":600}]}"""
        val (provider, client) = provider(listOf(existing to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(1, client.sent.size, "nothing may be written when nothing changed")
    }

    @Test
    fun `a lookup that returns a mismatched name is not trusted`() = runTest {
        val mismatched =
            """{"items":[{"recordId":"rec_1","type":"A","name":"other","data":"198.51.100.9"}]}"""
        val (provider, client) = provider(listOf(mismatched to 200, "{}" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        assertEquals("POST", client.sent.last().method)
    }

    @Test
    fun `one rejected record does not abandon the rest`() = runTest {
        val (provider, _) = provider(
            listOf(
                emptyItems,
                """{"code":"DUPLICATE_RECORD","message":"a record already exists"}""" to 422,
                emptyItems,
                "{}" to 200,
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
            provider(listOf("""{"code":"NOT_FOUND","message":"zone not found"}""" to 404))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        val failure = outcomes.first().result
        assertTrue(failure is DNSPublishOutcome.Result.Failed)
        assertTrue(failure.message.contains("example.com"))
    }
}

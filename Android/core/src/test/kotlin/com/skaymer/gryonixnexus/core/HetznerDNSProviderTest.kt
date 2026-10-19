package com.skaymer.gryonixnexus.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `HetznerDNSProviderTests` */
class HetznerDNSProviderTest {
    private val base = "https://api.example.test/v1"

    private fun provider(responses: List<Pair<String, Int>>):
        Pair<HetznerDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return HetznerDNSProvider("test-token", client, base) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private val zoneLookup = """{"zones":[{"id":"zone123","name":"example.com"}]}""" to 200
    private val emptyRecords =
        """{"records":[],"meta":{"pagination":{"page":1,"last_page":1}}}""" to 200

    // ------------------------------------------------------------- Auth

    @Test
    fun `the token goes up as auth-api-token`() = runTest {
        val (provider, client) = provider(listOf(zoneLookup, emptyRecords, "{}" to 200))
        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )
        assertEquals("test-token", client.sent.first().headers["Auth-API-Token"])
    }

    @Test
    fun `verify token reads one zone and writes nothing`() = runTest {
        val (provider, client) = provider(listOf("""{"zones":[]}""" to 200))
        provider.verifyToken()
        assertEquals(listOf("GET"), client.sent.map { it.method })
    }

    @Test
    fun `an invalid token is reported plainly`() = runTest {
        val (provider, _) =
            provider(listOf("""{"error":{"message":"invalid auth","code":401}}""" to 401))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: HetznerError) {
            assertEquals(HetznerError.InvalidToken, error)
        }
    }

    // ------------------------------------------------------------ Writing

    @Test
    fun `a missing record is created with a relative name`() = runTest {
        val (provider, client) = provider(listOf(zoneLookup, emptyRecords, "{}" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        val create = client.sent.last()
        assertEquals("POST", create.method)
        assertEquals("$base/records", create.url)
        val body = assertNotNull(client.lastBody())
        assertEquals("zone123", body["zone_id"]?.jsonPrimitive?.content)
        assertEquals("A", body["type"]?.jsonPrimitive?.content)
        assertEquals("mail", body["name"]?.jsonPrimitive?.content)
        assertEquals("203.0.113.4", body["value"]?.jsonPrimitive?.content)
    }

    @Test
    fun `an apex record is named at`() = runTest {
        val (provider, client) = provider(listOf(zoneLookup, emptyRecords, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals("@", client.lastBody()?.get("name")?.jsonPrimitive?.content)
    }

    @Test
    fun `an MX record folds the priority into the value`() = runTest {
        val (provider, client) = provider(listOf(zoneLookup, emptyRecords, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)),
            "example.com",
        )

        assertEquals("10 mail.example.com.", client.lastBody()?.get("value")?.jsonPrimitive?.content)
    }

    @Test
    fun `an SRV record folds all four fields into the value`() = runTest {
        val (provider, client) = provider(listOf(zoneLookup, emptyRecords, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(
                DNSRecord.service(
                    name = "_sip._tcp.example.com",
                    srv = DNSRecord.SRVData(priority = 0, weight = 5, port = 5060, target = "sip.example.com"),
                ),
            ),
            "example.com",
        )

        assertEquals("0 5 5060 sip.example.com.", client.lastBody()?.get("value")?.jsonPrimitive?.content)
    }

    @Test
    fun `a changed record is updated in place`() = runTest {
        val existing = """{"records":[{"id":"rec1","type":"A","name":"mail","value":"198.51.100.9"}],
            "meta":{"pagination":{"page":1,"last_page":1}}}"""
        val (provider, client) = provider(listOf(zoneLookup, existing to 200, "{}" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        assertEquals("PUT", client.sent.last().method)
        assertEquals("$base/records/rec1", client.sent.last().url)
    }

    @Test
    fun `an identical record is left alone`() = runTest {
        val existing = """{"records":[{"id":"rec1","type":"A","name":"mail","value":"203.0.113.4"}],
            "meta":{"pagination":{"page":1,"last_page":1}}}"""
        val (provider, client) = provider(listOf(zoneLookup, existing to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(2, client.sent.size, "nothing may be written when nothing changed")
    }

    @Test
    fun `pagination follows last_page not a short final batch`() = runTest {
        val full = "{\"records\":[" + (1..100).joinToString(",") {
            "{\"id\":\"r$it\",\"type\":\"A\",\"name\":\"h$it\",\"value\":\"203.0.113.4\"}"
        } + "],\"meta\":{\"pagination\":{\"page\":1,\"last_page\":1}}}"
        val (provider, client) = provider(listOf(zoneLookup, full to 200, "{}" to 200))

        provider.publishReportingOutcomes(
            listOf(record("new.example.com", DNSRecord.RecordType.A, "203.0.113.9")),
            "example.com",
        )

        assertEquals(3, client.sent.size, "a last_page of 1 must not fetch a second page")
    }
}

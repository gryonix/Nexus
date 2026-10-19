package com.skaymer.gryonixnexus.core

import java.security.MessageDigest
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `OVHDNSProviderTests` */
class OVHDNSProviderTest {
    private val base = "https://api.example.test/1.0"
    private val serverNow = 1_700_000_000L
    private val localNow = 1_699_999_990L

    private fun provider(
        responses: List<Pair<String, Int>>,
        token: String = "APPKEY:APPSECRET:CONSUMER",
    ): Pair<OVHDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return OVHDNSProvider(token, client, base, nowSeconds = { localNow }) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private val time = serverNow.toString() to 200
    private val nullOK = "null" to 200
    private val noRecords = "[]" to 200

    private fun signature(
        secret: String = "APPSECRET",
        consumer: String = "CONSUMER",
        method: String,
        url: String,
        body: String = "",
        timestamp: String = "1700000000",
    ): String {
        val base = listOf(secret, consumer, method, url, body, timestamp).joinToString("+")
        val digest = MessageDigest.getInstance("SHA-1").digest(base.toByteArray(Charsets.UTF_8))
        return "\$1\$" + digest.joinToString("") { "%02x".format(it) }
    }

    // ------------------------------------------------------------- Auth

    @Test
    fun `fewer than three keys is refused before any request`() = runTest {
        val (provider, client) = provider(emptyList(), token = "APPKEY:APPSECRET")
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: OVHError) {
            assertEquals(OVHError.MalformedToken, error)
        }
        assertTrue(client.sent.isEmpty(), "a malformed token must not reach the network")
    }

    @Test
    fun `a colon inside the consumer key stays in it`() = runTest {
        val (provider, client) = provider(listOf(time, noRecords), token = "AK:AS:CK:with:colons")
        provider.verifyToken()
        val verify = client.sent.last()
        assertEquals("AK", verify.headers["X-Ovh-Application"])
        assertEquals(
            signature(secret = "AS", consumer = "CK:with:colons", method = "GET", url = verify.url),
            verify.headers["X-Ovh-Signature"],
        )
    }

    @Test
    fun `verify token lists zones and writes nothing`() = runTest {
        val (provider, client) = provider(listOf(time, """["example.com"]""" to 200))
        provider.verifyToken()
        assertEquals(listOf("GET", "GET"), client.sent.map { it.method })
        assertEquals("$base/auth/time", client.sent.first().url)
        assertEquals("$base/domain/zone", client.sent.last().url)
    }

    @Test
    fun `a signed request carries the four headers`() = runTest {
        val (provider, client) = provider(listOf(time, """["example.com"]""" to 200))
        provider.verifyToken()
        val verify = client.sent.last()
        assertEquals("APPKEY", verify.headers["X-Ovh-Application"])
        assertEquals("CONSUMER", verify.headers["X-Ovh-Consumer"])
        assertEquals("1700000000", verify.headers["X-Ovh-Timestamp"])
        assertEquals(signature(method = "GET", url = verify.url), verify.headers["X-Ovh-Signature"])
        // The unauthenticated /auth/time call is not signed.
        assertNull(client.sent.first().headers["X-Ovh-Signature"])
    }

    @Test
    fun `a forbidden answer is reported as an invalid token`() = runTest {
        val (provider, _) = provider(listOf(time, """{"message":"Invalid signature"}""" to 403))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: OVHError) {
            assertEquals(OVHError.InvalidToken, error)
        }
    }

    // ---------------------------------------------------------- Writing

    @Test
    fun `a missing record is created relative and the zone is refreshed`() = runTest {
        val (provider, client) = provider(
            listOf(time, noRecords, """{"id":1,"target":"203.0.113.4"}""" to 200, nullOK),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        // auth/time, the filtered list, the create, then the refresh.
        assertEquals(listOf("GET", "GET", "POST", "POST"), client.sent.map { it.method })
        val list = client.sent[1]
        assertEquals(
            "$base/domain/zone/example.com/record?fieldType=A&subDomain=mail",
            list.url,
        )
        val create = client.sent[2]
        assertEquals("$base/domain/zone/example.com/record", create.url)
        assertEquals("A", client.body(2)?.get("fieldType")?.jsonPrimitive?.content)
        assertEquals("mail", client.body(2)?.get("subDomain")?.jsonPrimitive?.content)
        assertEquals("203.0.113.4", client.body(2)?.get("target")?.jsonPrimitive?.content)
        assertEquals("$base/domain/zone/example.com/refresh", client.sent.last().url)
    }

    @Test
    fun `an apex record has a blank subdomain`() = runTest {
        val (provider, client) = provider(
            listOf(time, noRecords, """{"id":1}""" to 200, nullOK),
        )

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals("", client.body(2)?.get("subDomain")?.jsonPrimitive?.content)
        assertEquals(
            "$base/domain/zone/example.com/record?fieldType=A&subDomain=",
            client.sent[1].url,
        )
    }

    @Test
    fun `an mx record folds the priority into the target`() = runTest {
        val (provider, client) = provider(listOf(time, noRecords, """{"id":1}""" to 200, nullOK))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)),
            "example.com",
        )

        assertEquals("10 mail.example.com.", client.body(2)?.get("target")?.jsonPrimitive?.content)
    }

    @Test
    fun `a changed record is updated by id and refreshed`() = runTest {
        val (provider, client) = provider(
            listOf(
                time,
                """[42]""" to 200,
                """{"id":42,"subDomain":"mail","fieldType":"A","target":"198.51.100.9","ttl":3600}""" to 200,
                nullOK,
                nullOK,
            ),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        val put = client.sent[3]
        assertEquals("PUT", put.method)
        assertEquals("$base/domain/zone/example.com/record/42", put.url)
        assertEquals("203.0.113.4", client.body(3)?.get("target")?.jsonPrimitive?.content)
        assertEquals("$base/domain/zone/example.com/refresh", client.sent.last().url)
    }

    @Test
    fun `an identical record is left alone and nothing is refreshed`() = runTest {
        val (provider, client) = provider(
            listOf(time, """[42]""" to 200, """{"id":42,"target":"203.0.113.4"}""" to 200),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(3, client.sent.size, "an up-to-date record writes nothing and skips the refresh")
    }

    @Test
    fun `a trailing dot on a host target does not force an update`() = runTest {
        val (provider, _) = provider(
            listOf(time, """[7]""" to 200, """{"id":7,"target":"1 mail.example.com"}""" to 200),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 1)),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
    }

    @Test
    fun `a missing zone is named in the error`() = runTest {
        val (provider, _) = provider(listOf(time, """{"message":"This service does not exist"}""" to 404))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.nope.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "nope.com",
        )

        val failure = outcomes.first().result as? DNSPublishOutcome.Result.Failed
            ?: fail("expected a per-record failure")
        assertTrue(failure.message.contains("nope.com"), "the missing zone should be named: ${failure.message}")
    }
}

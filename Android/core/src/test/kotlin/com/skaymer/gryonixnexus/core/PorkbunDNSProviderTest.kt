package com.skaymer.gryonixnexus.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `PorkbunDNSProviderTests` */
class PorkbunDNSProviderTest {
    private val base = "https://api.example.test/v3"

    private fun provider(
        responses: List<Pair<String, Int>>,
        token: String = "test-key:test-secret",
    ): Pair<PorkbunDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return PorkbunDNSProvider(token, client, base) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private val emptyRecords = """{"status":"SUCCESS","records":[]}""" to 200

    // ------------------------------------------------------------- Auth

    @Test
    fun `both keys go up in the body`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"status":"SUCCESS","id":"1"}""" to 200))
        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )
        val body = assertNotNull(client.body(0))
        assertEquals("test-key", body["apikey"]?.jsonPrimitive?.content)
        assertEquals("test-secret", body["secretapikey"]?.jsonPrimitive?.content)
    }

    @Test
    fun `a colon inside the secret stays in the secret`() = runTest {
        val (provider, client) = provider(
            listOf(emptyRecords, """{"status":"SUCCESS","id":"1"}""" to 200),
            token = "key:secret:with:colons",
        )
        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )
        val body = assertNotNull(client.body(0))
        assertEquals("key", body["apikey"]?.jsonPrimitive?.content)
        assertEquals("secret:with:colons", body["secretapikey"]?.jsonPrimitive?.content)
    }

    @Test
    fun `a missing colon is refused before any request`() = runTest {
        val (provider, client) = provider(emptyList(), token = "just-one-value")
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: PorkbunError) {
            assertEquals(PorkbunError.MalformedToken, error)
        }
        assertTrue(client.sent.isEmpty(), "a malformed token must not reach the network")
    }

    @Test
    fun `verify token pings and writes nothing else`() = runTest {
        val (provider, client) = provider(
            listOf("""{"status":"SUCCESS","yourIp":"203.0.113.1","credentialsValid":true}""" to 200),
        )
        provider.verifyToken()
        assertEquals(listOf("POST"), client.sent.map { it.method })
        assertEquals("$base/ping", client.sent.first().url)
    }

    @Test
    fun `an invalid token is reported plainly`() = runTest {
        val (provider, _) = provider(listOf("""{"status":"ERROR","message":"Invalid API key."}""" to 400))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: PorkbunError) {
            assertEquals(PorkbunError.InvalidToken, error)
        }
    }

    // ------------------------------------------------------------ Writing

    @Test
    fun `a missing record is created with a relative name`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"status":"SUCCESS","id":"1"}""" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        val create = client.sent.last()
        assertEquals("POST", create.method)
        assertEquals("$base/dns/create/example.com", create.url)
        val body = assertNotNull(client.lastBody())
        assertEquals("A", body["type"]?.jsonPrimitive?.content)
        assertEquals("mail", body["name"]?.jsonPrimitive?.content)
        assertEquals("203.0.113.4", body["content"]?.jsonPrimitive?.content)
    }

    @Test
    fun `an apex record is named blank`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"status":"SUCCESS","id":"1"}""" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals("", client.lastBody()?.get("name")?.jsonPrimitive?.content)
    }

    @Test
    fun `an MX record sends priority as its own field`() = runTest {
        // Unlike Hetzner, Porkbun has its own `prio` field.
        val (provider, client) = provider(listOf(emptyRecords, """{"status":"SUCCESS","id":"1"}""" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)),
            "example.com",
        )

        val body = assertNotNull(client.lastBody())
        assertEquals("mail.example.com.", body["content"]?.jsonPrimitive?.content)
        assertEquals(10, body["prio"]?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `an SRV record sends the target as content and priority as prio`() = runTest {
        val (provider, client) = provider(listOf(emptyRecords, """{"status":"SUCCESS","id":"1"}""" to 200))

        provider.publishReportingOutcomes(
            listOf(
                DNSRecord.service(
                    name = "_sip._tcp.example.com",
                    srv = DNSRecord.SRVData(priority = 0, weight = 5, port = 5060, target = "sip.example.com"),
                ),
            ),
            "example.com",
        )

        val body = assertNotNull(client.lastBody())
        assertEquals("sip.example.com.", body["content"]?.jsonPrimitive?.content)
        assertEquals(0, body["prio"]?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `a changed record is updated by name and type`() = runTest {
        val existing = """{"status":"SUCCESS","records":[
            {"id":"rec1","type":"A","name":"mail.example.com","content":"198.51.100.9"}]}""" to 200
        val (provider, client) = provider(listOf(existing, """{"status":"SUCCESS"}""" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        val edit = client.sent.last()
        assertEquals("POST", edit.method)
        assertEquals("$base/dns/edit/example.com/rec1", edit.url)
        assertEquals("203.0.113.4", client.lastBody()?.get("content")?.jsonPrimitive?.content)
        assertEquals("mail", client.lastBody()?.get("name")?.jsonPrimitive?.content)
        assertEquals("A", client.lastBody()?.get("type")?.jsonPrimitive?.content)
    }

    @Test
    fun `an apex update sends an empty name`() = runTest {
        val existing = """{"status":"SUCCESS","records":[
            {"id":"rec1","type":"A","name":"example.com","content":"198.51.100.9"}]}""" to 200
        val (provider, client) = provider(listOf(existing, """{"status":"SUCCESS"}""" to 200))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals("$base/dns/edit/example.com/rec1", client.sent.last().url)
        assertEquals("", client.lastBody()?.get("name")?.jsonPrimitive?.content)
    }

    @Test
    fun `an identical record is left alone`() = runTest {
        val existing = """{"status":"SUCCESS","records":[
            {"id":"rec1","type":"A","name":"mail.example.com","content":"203.0.113.4"}]}""" to 200
        val (provider, client) = provider(listOf(existing))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(1, client.sent.size, "nothing may be written when nothing changed")
    }

    @Test
    fun `matching ignores a wrong name same type`() = runTest {
        val existing = """{"status":"SUCCESS","records":[
            {"id":"rec1","type":"A","name":"other.example.com","content":"198.51.100.9"}]}""" to 200
        val (provider, client) = provider(listOf(existing, """{"status":"SUCCESS","id":"1"}""" to 200))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        assertEquals("$base/dns/create/example.com", client.sent.last().url)
    }
}

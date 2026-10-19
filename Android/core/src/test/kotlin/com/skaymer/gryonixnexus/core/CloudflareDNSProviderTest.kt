package com.skaymer.gryonixnexus.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `CloudflareDNSProviderTests` */
class CloudflareDNSProviderTest {
    private val base = "https://api.example.test/client/v4"
    private val zoneLookup = """[{"id":"zone123","name":"example.com"}]"""

    private fun provider(responses: List<Pair<String, Int>>):
        Pair<CloudflareDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return CloudflareDNSProvider("test-token", client, base) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    // ------------------------------------------------------------- Writing

    @Test
    fun `a missing record is created`() = runTest {
        val (provider, client) = provider(listOf(ok(zoneLookup), ok("[]"), ok("{}")))

        val outcomes = provider.applyReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Created), outcomes.map { it.result })
        val create = client.sent.last()
        assertEquals("POST", create.method)
        assertEquals("$base/zones/zone123/dns_records", create.url)
        val body = assertNotNull(client.lastBody())
        assertEquals("A", body["type"]?.jsonPrimitive?.content)
        assertEquals("mail.example.com", body["name"]?.jsonPrimitive?.content)
        assertEquals("203.0.113.4", body["content"]?.jsonPrimitive?.content)
    }

    @Test
    fun `records are never proxied`() = runTest {
        val (provider, client) = provider(listOf(ok(zoneLookup), ok("[]"), ok("{}")))

        provider.applyReportingOutcomes(
            listOf(record("vpn.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(false, client.lastBody()?.get("proxied")?.jsonPrimitive?.booleanOrNull)
    }

    @Test
    fun `a changed record is updated in place`() = runTest {
        val existing =
            """[{"id":"rec1","type":"A","name":"mail.example.com","content":"198.51.100.9"}]"""
        val (provider, client) = provider(listOf(ok(zoneLookup), ok(existing), ok("{}")))

        val outcomes = provider.applyReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Updated), outcomes.map { it.result })
        assertEquals("PUT", client.sent.last().method)
        assertEquals("$base/zones/zone123/dns_records/rec1", client.sent.last().url)
    }

    /** Re-running must write nothing */
    @Test
    fun `an identical record is left alone`() = runTest {
        val existing =
            """[{"id":"rec1","type":"A","name":"mail.example.com","content":"203.0.113.4"}]"""
        val (provider, client) = provider(listOf(ok(zoneLookup), ok(existing)))

        val outcomes = provider.applyReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(2, client.sent.size, "nothing may be written when nothing changed")
    }

    /** Cloudflare lower-cases names; the generator does not promise to */
    @Test
    fun `matching ignores name case`() = runTest {
        val existing =
            """[{"id":"rec1","type":"A","name":"mail.example.com","content":"203.0.113.4"}]"""
        val (provider, _) = provider(listOf(ok(zoneLookup), ok(existing)))

        val outcomes = provider.applyReportingOutcomes(
            listOf(record("MAIL.Example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Unchanged), outcomes.map { it.result })
    }

    @Test
    fun `MX priority counts as a change`() = runTest {
        val existing = """
            [{"id":"rec1","type":"MX","name":"example.com","content":"mail.example.com","priority":20}]
        """.trimIndent()
        val (provider, client) = provider(listOf(ok(zoneLookup), ok(existing), ok("{}")))

        val outcomes = provider.applyReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)),
            "example.com",
        )

        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Updated), outcomes.map { it.result })
        assertEquals(10, client.lastBody()?.get("priority")?.jsonPrimitive?.content?.toInt())
    }

    @Test
    fun `removal takes only the records pointing at the server`() = runTest {
        val existing = """[{"id":"a1","type":"A","name":"vault.example.com","content":"203.0.113.4"},{"id":"a2","type":"A","name":"vault.example.org","content":"198.51.100.9"}]"""
        val (provider, client) = provider(listOf(ok(zoneLookup), ok(existing), ok("{}")))
        val removed = provider.removeAddressRecords(listOf("vault.example.com", "vault.example.org"), "203.0.113.4", "example.com")
        assertEquals(listOf("vault.example.com"), removed)
        assertEquals("DELETE", client.sent.last().method)
        assertTrue(client.sent.last().url.endsWith("dns_records/a1"))
    }

    @Test
    fun `long TXT values are sent whole`() = runTest {
        val key = "v=DKIM1; k=rsa; p=" + "A".repeat(400)
        val (provider, client) = provider(listOf(ok(zoneLookup), ok("[]"), ok("{}")))

        provider.applyReportingOutcomes(
            listOf(record("dkim._domainkey.example.com", DNSRecord.RecordType.TXT, key)),
            "example.com",
        )

        assertEquals("\"$key\"", client.lastBody()?.get("content")?.jsonPrimitive?.content)
    }

    @Test
    fun `a quoted TXT record is already correct, an unquoted one is rewritten`() = runTest {
        val quoted = """[{"id":"rec1","type":"TXT","name":"example.com","content":"\"v=spf1 mx \" \"-all\""}]"""
        val (first, _) = provider(listOf(ok(zoneLookup), ok(quoted)))
        val kept = first.applyReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.TXT, "v=spf1 mx -all")), "example.com")
        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Unchanged), kept.map { it.result })

        val bare = """[{"id":"rec1","type":"TXT","name":"example.com","content":"v=spf1 mx -all"}]"""
        val (second, client) = provider(listOf(ok(zoneLookup), ok(bare), ok("{}")))
        val rewritten = second.applyReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.TXT, "v=spf1 mx -all")), "example.com")
        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Updated), rewritten.map { it.result })
        assertEquals("\"v=spf1 mx -all\"", client.lastBody()?.get("content")?.jsonPrimitive?.content)
    }

    @Test
    fun `SPF leaves another TXT at the same name alone and updates an old SPF`() = runTest {
        val spf = record("example.com", DNSRecord.RecordType.TXT, "v=spf1 mx -all")
        val other = """[{"id":"rec1","type":"TXT","name":"example.com","content":"\"google-site-verification=abc\""}]"""
        val (first, _) = provider(listOf(ok(zoneLookup), ok(other), ok("{}")))
        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Created),
            first.applyReportingOutcomes(listOf(spf), "example.com").map { it.result })

        val both = """[{"id":"rec1","type":"TXT","name":"example.com","content":"\"google-site-verification=abc\""},
            {"id":"rec2","type":"TXT","name":"example.com","content":"\"v=spf1 a -all\""}]"""
        val (second, _) = provider(listOf(ok(zoneLookup), ok(both), ok("{}")))
        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Updated),
            second.applyReportingOutcomes(listOf(spf), "example.com").map { it.result })
    }

    @Test
    fun `one rejected record does not stop the rest`() = runTest {
        val conflict = """
            {"success":false,"errors":[{"code":81053,"message":"An A record with that host already exists."}],"result":null}
        """.trimIndent() to 400
        val (provider, _) = provider(listOf(ok(zoneLookup), ok("[]"), conflict, ok("{}")))

        val outcomes = provider.applyReportingOutcomes(
            listOf(
                record("a.example.com", DNSRecord.RecordType.A, "203.0.113.4"),
                record("b.example.com", DNSRecord.RecordType.A, "203.0.113.5"),
            ),
            "example.com",
        )

        assertEquals(2, outcomes.size)
        val failed = outcomes[0].result
        assertTrue(failed is CloudflareDNSProvider.Outcome.Result.Failed, "got $failed")
        assertTrue(failed.message.contains("already exists"), failed.message)
        assertEquals(CloudflareDNSProvider.Outcome.Result.Created, outcomes[1].result)
    }

    @Test
    fun `every page of existing records is read`() = runTest {
        val firstPage = (0 until 100).joinToString(",") {
            """{"id":"r$it","type":"A","name":"h$it.example.com","content":"203.0.113.1"}"""
        }
        val secondPage =
            """[{"id":"rec2","type":"A","name":"mail.example.com","content":"203.0.113.4"}]"""
        val (provider, client) = provider(listOf(ok(zoneLookup), ok("[$firstPage]"), ok(secondPage)))

        val outcomes = provider.applyReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
            "example.com",
        )

        assertEquals(listOf(CloudflareDNSProvider.Outcome.Result.Unchanged), outcomes.map { it.result })
        assertTrue(client.sent[2].url.contains("page=2"), client.sent[2].url)
    }

    // ------------------------------------------------------- Zone and token

    @Test
    fun `zone lookup uses the name the owner typed`() = runTest {
        val (provider, client) = provider(listOf(ok(zoneLookup)))

        assertEquals("zone123", provider.zoneID("example.com"))

        assertEquals("$base/zones?name=example.com", client.sent.first().url)
        assertEquals("Bearer test-token", client.sent.first().headers["Authorization"])
    }

    @Test
    fun `a zone this account does not hold is named`() = runTest {
        val (provider, _) = provider(listOf(ok("[]")))

        val error = runCatching { provider.zoneID("somebody-elses.com") }.exceptionOrNull()

        assertEquals(CloudflareError.ZoneNotFound("somebody-elses.com"), error)
    }

    @Test
    fun `the real invalid token response is recognised`() = runTest {
        val body = """
            {"success":false,"errors":[{"code":1000,"message":"Invalid API Token"}],"messages":[],"result":null}
        """.trimIndent()
        val (provider, _) = provider(listOf(body to 401))

        assertEquals(
            CloudflareError.InvalidToken,
            runCatching { provider.verifyToken() }.exceptionOrNull(),
        )
    }

    @Test
    fun `the real malformed header response is recognised`() = runTest {
        val body = """
            {"success":false,"errors":[{"code":6003,"message":"Invalid request headers","error_chain":[{"code":6111,"message":"Invalid format for Authorization header"}]}],"messages":[],"result":null}
        """.trimIndent()
        val (provider, _) = provider(listOf(body to 400))

        assertEquals(
            CloudflareError.InvalidToken,
            runCatching { provider.verifyToken() }.exceptionOrNull(),
        )
    }

    @Test
    fun `a failure inside a two hundred is still a failure`() = runTest {
        val body = """
            {"success":false,"errors":[{"code":7003,"message":"Could not route to /zones"}],"result":null}
        """.trimIndent()
        val (provider, _) = provider(listOf(body to 200))

        assertEquals(
            CloudflareError.Api(7003, "Could not route to /zones"),
            runCatching { provider.verifyToken() }.exceptionOrNull(),
        )
    }

    // ----------------------------------------------------------------- SRV

    @Test
    fun `an SRV record goes up as an object and is not rewritten when unchanged`() = runTest {
        val srv = DNSRecord.SRVData(priority = 0, weight = 5, port = 25565, target = "mc.example.com")
        val record = DNSRecord.service("_minecraft._tcp.example.com", srv)

        val (creating, client) = provider(listOf(ok(zoneLookup), ok("[]"), ok("{}")))
        creating.applyReportingOutcomes(listOf(record), "example.com")

        val data = assertNotNull(client.lastBody()?.get("data"))
        assertEquals(
            """{"port":25565,"priority":0,"target":"mc.example.com","weight":5}""",
            data.toString(),
        )

        val withoutPriority = """
            [{"id":"rec1","type":"SRV","name":"_minecraft._tcp.example.com",
              "content":"5 25565 mc.example.com","priority":0}]
        """.trimIndent()
        val (rerun, rerunClient) = provider(listOf(ok(zoneLookup), ok(withoutPriority)))

        assertEquals(
            listOf(CloudflareDNSProvider.Outcome.Result.Unchanged),
            rerun.applyReportingOutcomes(listOf(record), "example.com").map { it.result },
        )
        assertEquals(2, rerunClient.sent.size, "an unchanged SRV must not be rewritten")

        val withPriority = """
            [{"id":"rec1","type":"SRV","name":"_minecraft._tcp.example.com",
              "content":"0 5 25565 mc.example.com","priority":0}]
        """.trimIndent()
        val (echoed, _) = provider(listOf(ok(zoneLookup), ok(withPriority)))
        assertEquals(
            listOf(CloudflareDNSProvider.Outcome.Result.Unchanged),
            echoed.applyReportingOutcomes(listOf(record), "example.com").map { it.result },
        )

        val moved = """
            [{"id":"rec1","type":"SRV","name":"_minecraft._tcp.example.com",
              "content":"5 25566 mc.example.com","priority":0}]
        """.trimIndent()
        val (changed, _) = provider(listOf(ok(zoneLookup), ok(moved), ok("{}")))
        assertEquals(
            listOf(CloudflareDNSProvider.Outcome.Result.Updated),
            changed.applyReportingOutcomes(listOf(record), "example.com").map { it.result },
        )
    }

    /** Also not in the Swift twin */
    @Test
    fun `request bodies are sorted at every depth`() = runTest {
        val srv = DNSRecord.SRVData(priority = 1, weight = 2, port = 3, target = "t.example.com")
        val (provider, client) = provider(listOf(ok(zoneLookup), ok("[]"), ok("{}")))

        provider.applyReportingOutcomes(
            listOf(DNSRecord.service("_svc._tcp.example.com", srv, comment = "a comment")),
            "example.com",
        )

        assertEquals(
            """{"comment":"a comment","content":"1 2 3 t.example.com",""" +
                """"data":{"port":3,"priority":1,"target":"t.example.com","weight":2},""" +
                """"name":"_svc._tcp.example.com","priority":1,"proxied":false,""" +
                """"ttl":1,"type":"SRV"}""",
            client.sent.last().body,
        )
    }
}

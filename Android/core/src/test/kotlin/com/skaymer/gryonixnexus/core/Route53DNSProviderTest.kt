package com.skaymer.gryonixnexus.core

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `Route53DNSProviderTests` */
class Route53DNSProviderTest {
    private val base = "https://route53.amazonaws.com"
    private val fixedNowMillis = 1_700_000_000_000L

    private fun provider(
        responses: List<Pair<String, Int>>,
        token: String = "AKIAEXAMPLE:secretkeyexample",
    ): Pair<Route53DNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return Route53DNSProvider(token, client, base, nowMillis = { fixedNowMillis }) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private fun ok(body: String): Pair<String, Int> = body to 200

    private fun zoneList(id: String = "/hostedzone/Z1PA6795UKMFR9", name: String = "example.com."): String =
        "<?xml version=\"1.0\"?><ListHostedZonesByNameResponse><HostedZones><HostedZone>" +
            "<Id>$id</Id><Name>$name</Name><CallerReference>x</CallerReference>" +
            "</HostedZone></HostedZones><IsTruncated>false</IsTruncated></ListHostedZonesByNameResponse>"

    private fun emptyRecordSets(): String =
        "<?xml version=\"1.0\"?><ListResourceRecordSetsResponse><ResourceRecordSets/>" +
            "<IsTruncated>false</IsTruncated></ListResourceRecordSetsResponse>"

    private fun recordSet(name: String, type: String, ttl: Int, values: List<String>): String {
        val recs = values.joinToString("") { "<ResourceRecord><Value>$it</Value></ResourceRecord>" }
        return "<?xml version=\"1.0\"?><ListResourceRecordSetsResponse><ResourceRecordSets><ResourceRecordSet>" +
            "<Name>$name</Name><Type>$type</Type><TTL>$ttl</TTL>" +
            "<ResourceRecords>$recs</ResourceRecords></ResourceRecordSet></ResourceRecordSets>" +
            "<IsTruncated>false</IsTruncated></ListResourceRecordSetsResponse>"
    }

    private val changeOK = "<?xml version=\"1.0\"?><ChangeResourceRecordSetsResponse><ChangeInfo>" +
        "<Id>x</Id><Status>PENDING</Status></ChangeInfo></ChangeResourceRecordSetsResponse>"

    // ------------------------------------------------------------- Auth

    @Test
    fun `a missing colon is refused before any request`() = runTest {
        val (provider, client) = provider(emptyList(), token = "no-colon-here")
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: Route53Error) {
            assertEquals(Route53Error.MalformedToken, error)
        }
        assertTrue(client.sent.isEmpty(), "a malformed token must not reach the network")
    }

    @Test
    fun `verify token lists zones and writes nothing`() = runTest {
        val (provider, client) = provider(listOf(ok("<ListHostedZonesResponse/>")))
        provider.verifyToken()
        assertEquals(listOf("GET"), client.sent.map { it.method })
        assertEquals("$base/2013-04-01/hostedzone", client.sent.first().url)
    }

    @Test
    fun `the authorization header carries the credential scope and signed headers`() = runTest {
        val (provider, client) = provider(listOf(ok("<ListHostedZonesResponse/>")))
        provider.verifyToken()
        val auth = client.sent.first().headers["Authorization"] ?: fail("no Authorization header")
        assertTrue(
            auth.startsWith("AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20231114/us-east-1/route53/aws4_request, "),
            "unexpected credential scope: $auth",
        )
        assertTrue(auth.contains("SignedHeaders=host;x-amz-date, "), "unexpected signed headers: $auth")
        val signature = auth.substringAfter("Signature=")
        assertEquals(64, signature.length, "a SHA256 HMAC hex-encodes to 64 characters: $signature")
        assertTrue(signature.all { it.isDigit() || it in 'a'..'f' }, "the signature must be lowercase hex: $signature")
    }

    @Test
    fun `the signature matches an independent computation`() = runTest {
        val (provider, client) = provider(listOf(ok("<ListHostedZonesResponse/>")))
        provider.verifyToken()
        val request = client.sent.first()
        val amzDate = request.headers["X-Amz-Date"] ?: fail("no X-Amz-Date header")
        val dateStamp = amzDate.substring(0, 8)

        val payloadHash = sha256Hex("")
        val canonicalHeaders = "host:route53.amazonaws.com\nx-amz-date:$amzDate\n"
        val canonicalRequest = listOf(
            "GET", "/2013-04-01/hostedzone", "", canonicalHeaders, "host;x-amz-date", payloadHash,
        ).joinToString("\n")
        val scope = "$dateStamp/us-east-1/route53/aws4_request"
        val stringToSign = listOf(
            "AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(canonicalRequest),
        ).joinToString("\n")

        val kSecret = "AWS4secretkeyexample".toByteArray(Charsets.UTF_8)
        val kDate = hmacBytes(kSecret, dateStamp)
        val kRegion = hmacBytes(kDate, "us-east-1")
        val kService = hmacBytes(kRegion, "route53")
        val kSigning = hmacBytes(kService, "aws4_request")
        val expected = hmacBytes(kSigning, stringToSign).joinToString("") { "%02x".format(it) }

        val auth = request.headers["Authorization"] ?: fail("no Authorization header")
        assertEquals(expected, auth.substringAfter("Signature="))
    }

    private fun sha256Hex(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun hmacBytes(key: ByteArray, data: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data.toByteArray(Charsets.UTF_8))
    }

    @Test
    fun `a forbidden answer is reported as an invalid token`() = runTest {
        val (provider, _) = provider(listOf("<ErrorResponse/>" to 403))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: Route53Error) {
            assertEquals(Route53Error.InvalidToken, error)
        }
    }

    // ------------------------------------------------------------- Zone lookup

    @Test
    fun `a zone name that does not match is reported as not found`() = runTest {
        // ListHostedZonesByName returns the next zone ALPHABETICALLY, not necessarily a match.
        val (provider, _) = provider(listOf(ok(zoneList(name = "example.org."))))
        try {
            provider.publishReportingOutcomes(
                listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")),
                "example.com",
            )
            fail("expected an error")
        } catch (error: Route53Error) {
            assertEquals(Route53Error.ZoneNotFound("example.com"), error)
        }
    }

    @Test
    fun `the hosted zone id prefix is stripped`() = runTest {
        val (provider, client) = provider(
            listOf(ok(zoneList(id = "/hostedzone/Z1PA6795UKMFR9")), ok(emptyRecordSets()), ok(changeOK)),
        )
        provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
        )
        assertTrue(client.sent.any { it.url.contains("/hostedzone/Z1PA6795UKMFR9/rrset") },
                  "expected the bare zone id in the rrset path: ${client.sent.map { it.url }}")
        assertTrue(client.sent.none { it.url.contains("hostedzone//hostedzone") })
    }

    // ------------------------------------------------------------- Writing

    @Test
    fun `a missing record is created with one value`() = runTest {
        val (provider, client) = provider(listOf(ok(zoneList()), ok(emptyRecordSets()), ok(changeOK)))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        val change = client.sent.last()
        assertEquals("POST", change.method)
        assertTrue(change.url.endsWith("/rrset"))
        val body = change.body ?: fail("no body sent")
        assertTrue(body.contains("<Action>UPSERT</Action>"))
        assertTrue(body.contains("<Name>mail.example.com</Name>"))
        assertTrue(body.contains("<Value>203.0.113.4</Value>"))
    }

    @Test
    fun `an existing single value match is unchanged and nothing is written`() = runTest {
        val (provider, client) = provider(
            listOf(ok(zoneList()), ok(recordSet("mail.example.com.", "A", 300, listOf("203.0.113.4")))),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(2, client.sent.size, "unchanged must not call ChangeResourceRecordSets")
    }

    @Test
    fun `an existing multi value set keeps its other values on update`() = runTest {
        val (provider, client) = provider(
            listOf(
                ok(zoneList()),
                ok(recordSet("example.com.", "A", 300, listOf("198.51.100.1", "198.51.100.2"))),
                ok(changeOK),
            ),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "198.51.100.3")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        val rawBody = client.sent.last().body
        for (value in listOf("198.51.100.1", "198.51.100.2", "198.51.100.3")) {
            assertTrue(rawBody?.contains("<Value>$value</Value>") == true, "missing $value in: $rawBody")
        }
    }

    @Test
    fun `a value already in a multi value set is unchanged`() = runTest {
        val (provider, client) = provider(
            listOf(ok(zoneList()), ok(recordSet("example.com.", "A", 300, listOf("198.51.100.1", "198.51.100.2")))),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "198.51.100.2")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(2, client.sent.size)
    }

    @Test
    fun `an mx record folds the priority into the value`() = runTest {
        val (provider, client) = provider(listOf(ok(zoneList()), ok(emptyRecordSets()), ok(changeOK)))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)), "example.com",
        )

        assertTrue(client.sent.last().body?.contains("<Value>10 mail.example.com.</Value>") == true)
    }

    @Test
    fun `a txt record is sent quoted`() = runTest {
        val (provider, client) = provider(listOf(ok(zoneList()), ok(emptyRecordSets()), ok(changeOK)))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.TXT, "v=spf1 -all")), "example.com",
        )

        val body = client.sent.last().body ?: fail("no body sent")
        assertTrue(
            body.contains("<Value>&quot;v=spf1 -all&quot;</Value>") || body.contains("<Value>\"v=spf1 -all\"</Value>"),
            "expected a quoted TXT value in: $body",
        )
    }

    @Test
    fun `a missing zone is named in the error`() = runTest {
        val (provider, _) = provider(
            listOf(ok("<ListHostedZonesByNameResponse><HostedZones/></ListHostedZonesByNameResponse>")),
        )

        try {
            provider.publishReportingOutcomes(
                listOf(record("mail.nope.com", DNSRecord.RecordType.A, "203.0.113.4")), "nope.com",
            )
            fail("expected an error")
        } catch (error: Route53Error) {
            assertEquals(Route53Error.ZoneNotFound("nope.com"), error)
        }
    }
}

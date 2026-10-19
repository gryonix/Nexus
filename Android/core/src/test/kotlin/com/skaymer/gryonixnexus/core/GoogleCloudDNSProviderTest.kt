package com.skaymer.gryonixnexus.core

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.RSAPublicKeySpec
import java.util.Base64
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.jupiter.api.Test

/** The Kotlin twin of `GoogleCloudDNSProviderTests` */
class GoogleCloudDNSProviderTest {
    private val base = "https://dns.example.test/dns/v1"
    private val fixedNowMillis = 1_700_000_000_000L

    private val testPrivateKeyPEM = """
        -----BEGIN PRIVATE KEY-----
        MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQD5wt9k/BD9isVC
        PkrLrU3WU5rIeg1Wb+U3avXMfW63ejED5nZh18hq0LI1SVI9Dzyzg0tu9CTdB/p5
        2847SxrDLrixmJd9vG+sz7MMzu5Se4auGy9Wv8jHlMbuIAeDUzeJtSZsMcW0YZlY
        /vBI2p4w8x1o4vBghhXB3o3egLQ/+mTLHRdHAWVVSZl/TLGuYVyFEOzmtV4VLkcs
        ILojy094Oy5/4zbv9HsuLYGKsjxUT/iq0TVbozfmWnMRUjAHDGGb0jFF7HEEczI8
        GXG3tsIbE0pliiQ/yFlrUOUls1e7ey9KShndVwGhcdA7S7IMSO+g7QLGAqkKWXZq
        nz9aDLYLAgMBAAECggEADKWs8QzAKEz60iQcK3yNTXlF6p+4Xy3vwHYLflBeGkjD
        6whxHcemEwQzkfX/H3wCPRQJiAb+FHpov5Twa3/RGhy0JrutKCVlNK3+/HraBi+e
        t60R7f85W1argB4usAK3WqMwQxhK6s7Qy6xIXjGonJ5WJejsw4zmoYuNSYmtsI0t
        Ke6OCgzL4xfUa8iVm7NwWX6p9hvKmRV/ojAUx2exbGxxWvJe6i5P42T/lAb3GQM6
        rrgLuVww2YbUUy1jAHMnefKpZg3K2Fweccf9G1Dq3wG4goR/jK0CO9E8NBSLFKYj
        /qLTomc/mckibDjt8C7BJADXqtB//1put6PXHA+UmQKBgQD+Gv4xWtIG7KAOxoXz
        s84kuL1lISJTyS9FIYG9WP2i375Gdw1AKYuyy/5NBYaQRyUPEUBT6K11n70kJgD5
        igPk/DuqKPJgxQObEh/IWC/SEYzQZvp5SZVPA+/+AEeaP8x6QMoQujX7MTvCNQn3
        gNrxeQUDBzLur73TjnRy3BFJbwKBgQD7n5aD4EWPM4izrr9iLKqyHjPh/3rjCq5f
        BUI0c1HsJpt4pM4bNGkGNiVJdEvoSOlGDLJXUetcCiE/BxRRwzwdgC5UdBm62z98
        LB4A73xW5x79m/1nQ8p9oo5Gj4ZPfwNnku7N/6c4IUExe1RedeZyVVvn08fnqZUi
        rVCl5f33JQKBgBFvpruaQMkq2XzKEIz9bIrGhnB3CpT3PCAhQXbNsXHIqpTJPIaH
        k0dsigGc/HPP/fH/vAtF7wkgMelWFkEJQGUpDasKbj9HpYyxfK7Rpk5i1+fA+TTz
        YKRwX7ptKHykHhLReUwWive2lCQqYYmzNNLW/AoOJ2eLdZobr0/mW+VPAoGAJQb6
        8zURh10iBK72YtAH3mYrZFpgDwEHX9w6PdWqfIHB5yL5YW949P0Kx6BhezEfgrtj
        kw3vAIBNHCVCjDWapwyxxKPBFYol8XPchm63cWJZYSCPTZ7gMVS2cxOzxAcAzUEF
        +zJfvRbHrSxk4fGfk7uT5q13gVOnKo8uivspQDECgYEAj/KenYslPL6il+L6k4I1
        X39lcfdKHMISDD2Qo868EVVDchxN1lH1/RlZ0huYJ4OAORyneqobURgslj39T1Iy
        kKtUULELJWaqnjVCTM166T9OkRSF3KgZdw8PrEcYcFXMPWijW2wd087AIBCzAR/k
        qlSZtoi6KDhhBpWb68hJNuE=
        -----END PRIVATE KEY-----
    """.trimIndent()

    private val testPublicKeyPEM by lazy {
        val priv = rsaPrivateKeyForTest(testPrivateKeyPEM) as java.security.interfaces.RSAPrivateCrtKey
        val pub = KeyFactory.getInstance("RSA")
            .generatePublic(RSAPublicKeySpec(priv.modulus, priv.publicExponent))
        pub
    }

    private fun rsaPrivateKeyForTest(pem: String): java.security.PrivateKey {
        val stripped = pem.replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace(Regex("\\s"), "")
        val der = Base64.getDecoder().decode(stripped)
        return KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(der))
    }

    private fun serviceAccountJSON(
        privateKey: String? = testPrivateKeyPEM,
        clientEmail: String? = "svc@test-project.iam.gserviceaccount.com",
        projectID: String? = "test-project",
        tokenURI: String? = null,
    ): String {
        val fields = mutableMapOf<String, kotlinx.serialization.json.JsonElement>()
        privateKey?.let { fields["private_key"] = JsonPrimitive(it) }
        clientEmail?.let { fields["client_email"] = JsonPrimitive(it) }
        projectID?.let { fields["project_id"] = JsonPrimitive(it) }
        tokenURI?.let { fields["token_uri"] = JsonPrimitive(it) }
        return Json.encodeToString(JsonObject.serializer(), JsonObject(fields))
    }

    private fun provider(
        responses: List<Pair<String, Int>>,
        token: String = serviceAccountJSON(),
    ): Pair<GoogleCloudDNSProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return GoogleCloudDNSProvider(token, client, base, nowMillis = { fixedNowMillis }) to client
    }

    private fun record(
        name: String,
        type: DNSRecord.RecordType,
        value: String,
        priority: Int? = null,
    ) = DNSRecord(name = name, type = type, value = value, priority = priority)

    private fun ok(body: String): Pair<String, Int> = body to 200

    private fun tokenOK(accessToken: String = "test-access-token"): Pair<String, Int> =
        ok("""{"access_token":"$accessToken","expires_in":3599,"token_type":"Bearer"}""")

    private fun zoneList(name: String = "example-com", dnsName: String = "example.com."): String =
        """{"managedZones":[{"name":"$name","dnsName":"$dnsName"}]}"""

    private val emptyRRSets = """{"rrsets":[]}"""

    private fun rrset(type: String, ttl: Int, values: List<String>): String {
        val quoted = values.joinToString(",") { "\"$it\"" }
        return """{"rrsets":[{"type":"$type","ttl":$ttl,"rrdatas":[$quoted]}]}"""
    }

    private val changesOK = """{"id":"1","status":"pending"}"""

    // ------------------------------------------------------------- Auth / credentials

    @Test
    fun `a malformed token is refused before any request`() = runTest {
        val (provider, client) = provider(emptyList(), token = "not json")
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: GoogleCloudDNSError) {
            assertEquals(GoogleCloudDNSError.MalformedToken, error)
        }
        assertTrue(client.sent.isEmpty(), "a malformed token must not reach the network")
    }

    @Test
    fun `a missing field is refused`() = runTest {
        val (provider, client) = provider(emptyList(), token = serviceAccountJSON(projectID = null))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: GoogleCloudDNSError) {
            assertEquals(GoogleCloudDNSError.MalformedToken, error)
        }
        assertTrue(client.sent.isEmpty())
    }

    @Test
    fun `verify token exchanges a jwt then lists zones and writes nothing`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok("""{"managedZones":[]}""")))
        provider.verifyToken()
        assertEquals(listOf("POST", "GET"), client.sent.map { it.method })
        assertEquals("https://oauth2.googleapis.com/token", client.sent[0].url)
        assertTrue(client.sent[1].url.startsWith("$base/projects/test-project/managedZones"))
        assertEquals("Bearer test-access-token", client.sent[1].headers["Authorization"])
    }

    @Test
    fun `the token exchange carries the jwt bearer grant`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok("""{"managedZones":[]}""")))
        provider.verifyToken()
        val body = client.sent.first().body ?: fail("no body sent")
        assertTrue(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"))
        assertTrue(body.contains("assertion="))
    }

    @Test
    fun `the jwt signature verifies against the keys own public half`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok("""{"managedZones":[]}""")))
        provider.verifyToken()
        val body = client.sent.first().body ?: fail("no body sent")
        val assertion = body.split("&").first { it.startsWith("assertion=") }
            .removePrefix("assertion=")
            .let { java.net.URLDecoder.decode(it, "UTF-8") }
        val parts = assertion.split(".")
        assertEquals(3, parts.size, "header.payload.signature")

        val signingInput = "${parts[0]}.${parts[1]}".toByteArray(Charsets.UTF_8)
        val signatureBytes = base64URLDecode(parts[2])

        val verifier = Signature.getInstance("SHA256withRSA")
        verifier.initVerify(testPublicKeyPEM)
        verifier.update(signingInput)
        assertTrue(verifier.verify(signatureBytes), "signature did not verify")

        val payload = Json.parseToJsonElement(String(base64URLDecode(parts[1]), Charsets.UTF_8)).jsonObject
        assertEquals("svc@test-project.iam.gserviceaccount.com", payload["iss"]?.let { (it as JsonPrimitive).content })
        assertEquals(
            "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
            payload["scope"]?.let { (it as JsonPrimitive).content },
        )
        assertEquals("https://oauth2.googleapis.com/token", payload["aud"]?.let { (it as JsonPrimitive).content })
        val iat = (payload["iat"] as JsonPrimitive).content.toLong()
        val exp = (payload["exp"] as JsonPrimitive).content.toLong()
        assertEquals(3600L, exp - iat)
    }

    private fun base64URLDecode(value: String): ByteArray {
        var padded = value.replace('-', '+').replace('_', '/')
        while (padded.length % 4 != 0) padded += "="
        return Base64.getDecoder().decode(padded)
    }

    @Test
    fun `an unauthorized token exchange is reported as invalid`() = runTest {
        val (provider, _) = provider(listOf("""{"error":"invalid_grant"}""" to 401))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: GoogleCloudDNSError) {
            assertEquals(GoogleCloudDNSError.InvalidToken, error)
        }
    }

    @Test
    fun `a forbidden zones call is reported as invalid`() = runTest {
        val (provider, _) = provider(listOf(tokenOK(), """{"error":{"message":"forbidden"}}""" to 403))
        try {
            provider.verifyToken()
            fail("expected an error")
        } catch (error: GoogleCloudDNSError) {
            assertEquals(GoogleCloudDNSError.InvalidToken, error)
        }
    }

    // ------------------------------------------------------------- Zone lookup

    @Test
    fun `a missing zone is named in the error`() = runTest {
        val (provider, _) = provider(listOf(tokenOK(), ok("""{"managedZones":[]}""")))
        try {
            provider.publishReportingOutcomes(
                listOf(record("mail.nope.com", DNSRecord.RecordType.A, "203.0.113.4")), "nope.com",
            )
            fail("expected an error")
        } catch (error: GoogleCloudDNSError) {
            assertEquals(GoogleCloudDNSError.ZoneNotFound("nope.com"), error)
        }
    }

    @Test
    fun `a zone name that does not match is not trusted`() = runTest {
        val (provider, _) = provider(listOf(tokenOK(), ok(zoneList(dnsName = "example.org."))))
        try {
            provider.publishReportingOutcomes(
                listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
            )
            fail("expected an error")
        } catch (error: GoogleCloudDNSError) {
            assertEquals(GoogleCloudDNSError.ZoneNotFound("example.com"), error)
        }
    }

    @Test
    fun `zone lookup follows next page token`() = runTest {
        val (provider, client) = provider(
            listOf(
                tokenOK(),
                ok("""{"managedZones":[{"name":"other-zone","dnsName":"other.com."}],"nextPageToken":"p2"}"""),
                ok(zoneList()),
                ok(emptyRRSets),
                ok(changesOK),
            ),
        )
        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
        )
        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        assertTrue(client.sent[2].url.contains("pageToken=p2"))
    }

    // ------------------------------------------------------------- Writing

    @Test
    fun `a missing record is created with one value`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)))

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Created), outcomes.map { it.result })
        val change = client.sent.last()
        assertEquals("POST", change.method)
        assertTrue(change.url.endsWith("/changes"))
        val body = client.lastBody() ?: fail("no body sent")
        val additions = body["additions"] as kotlinx.serialization.json.JsonArray
        val first = additions[0].jsonObject
        assertEquals("mail.example.com.", (first["name"] as JsonPrimitive).content)
        assertNull(body["deletions"], "nothing existed yet — no deletions expected")
    }

    @Test
    fun `an existing single value match is unchanged and nothing is written`() = runTest {
        val (provider, client) = provider(
            listOf(tokenOK(), ok(zoneList()), ok(rrset("A", 300, listOf("203.0.113.4")))),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("mail.example.com", DNSRecord.RecordType.A, "203.0.113.4")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(3, client.sent.size, "unchanged must not call changes.create")
    }

    @Test
    fun `an existing multi value set keeps its other values on update`() = runTest {
        val (provider, client) = provider(
            listOf(
                tokenOK(), ok(zoneList()),
                ok(rrset("A", 300, listOf("198.51.100.1", "198.51.100.2"))),
                ok(changesOK),
            ),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "198.51.100.3")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Updated), outcomes.map { it.result })
        val body = client.lastBody() ?: fail("no body sent")
        val addedValues = body.jsonArrayValues("additions")
        for (value in listOf("198.51.100.1", "198.51.100.2", "198.51.100.3")) {
            assertTrue(addedValues.contains(value), "missing $value in $addedValues")
        }
        val deletedValues = body.jsonArrayValues("deletions")
        assertEquals(listOf("198.51.100.1", "198.51.100.2"), deletedValues)
    }

    @Test
    fun `a value already in a multi value set is unchanged`() = runTest {
        val (provider, client) = provider(
            listOf(tokenOK(), ok(zoneList()), ok(rrset("A", 300, listOf("198.51.100.1", "198.51.100.2")))),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.A, "198.51.100.2")), "example.com",
        )

        assertEquals(listOf(DNSPublishOutcome.Result.Unchanged), outcomes.map { it.result })
        assertEquals(3, client.sent.size)
    }

    @Test
    fun `an mx record folds the priority into the value`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.MX, "mail.example.com", priority = 10)), "example.com",
        )

        val body = client.lastBody() ?: fail("no body sent")
        assertEquals(listOf("10 mail.example.com."), body.jsonArrayValues("additions"))
    }

    @Test
    fun `a srv record folds all four fields into the value`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)))

        provider.publishReportingOutcomes(
            listOf(
                DNSRecord.service(
                    "_minecraft._tcp.example.com",
                    DNSRecord.SRVData(priority = 0, weight = 5, port = 25565, target = "mc.example.com"),
                ),
            ),
            "example.com",
        )

        val body = client.lastBody() ?: fail("no body sent")
        assertEquals(listOf("0 5 25565 mc.example.com."), body.jsonArrayValues("additions"))
    }

    @Test
    fun `a txt record is sent quoted`() = runTest {
        val (provider, client) = provider(listOf(tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)))

        provider.publishReportingOutcomes(
            listOf(record("example.com", DNSRecord.RecordType.TXT, "v=spf1 -all")), "example.com",
        )

        val body = client.lastBody() ?: fail("no body sent")
        assertEquals(listOf("\"v=spf1 -all\""), body.jsonArrayValues("additions"))
    }

    @Test
    fun `one failed record does not abandon the rest`() = runTest {
        val (provider, _) = provider(
            listOf(
                tokenOK(), ok(zoneList()),
                """{"error":{"message":"quota exceeded"}}""" to 429,
                ok(emptyRRSets), ok(changesOK),
            ),
        )

        val outcomes = provider.publishReportingOutcomes(
            listOf(
                record("a.example.com", DNSRecord.RecordType.A, "203.0.113.4"),
                record("b.example.com", DNSRecord.RecordType.A, "203.0.113.5"),
            ),
            "example.com",
        )

        assertEquals(2, outcomes.size)
        assertTrue(outcomes[0].result is DNSPublishOutcome.Result.Failed, "expected the first record to fail")
        assertEquals(DNSPublishOutcome.Result.Created, outcomes[1].result)
    }

    /** The `rrdatas` of the first entry in `additions`/`deletions` */
    private fun JsonObject.jsonArrayValues(key: String): List<String> {
        val array = this[key] as? kotlinx.serialization.json.JsonArray ?: return emptyList()
        val first = array.firstOrNull()?.jsonObject ?: return emptyList()
        val rrdatas = first["rrdatas"] as? kotlinx.serialization.json.JsonArray ?: return emptyList()
        return rrdatas.map { (it as JsonPrimitive).content }
    }
}

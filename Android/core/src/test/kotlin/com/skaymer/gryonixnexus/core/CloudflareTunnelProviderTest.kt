package com.skaymer.gryonixnexus.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `CloudflareTunnelProviderTests` */
class CloudflareTunnelProviderTest {
    private val base = "https://api.example.test/client/v4"
    private val account = "acc123"

    private fun provider(responses: List<Pair<String, Int>>):
        Pair<CloudflareTunnelProvider, StubCloudflareClient> {
        val client = StubCloudflareClient(responses)
        return CloudflareTunnelProvider("t", account, client, base) to client
    }

    // ------------------------------------------------- Finding and creating

    @Test
    fun `an existing tunnel is reused rather than duplicated`() = runTest {
        val listing = """[{"id":"tun-1","name":"gryonixnexus-example-com"}]"""
        val (provider, client) = provider(listOf(ok(listing)))

        assertEquals("tun-1", provider.findOrCreateTunnel("gryonixnexus-example-com"))

        assertEquals(1, client.sent.size, "nothing may be created when one already exists")
        assertEquals("GET", client.sent[0].method)
        assertTrue(client.sent[0].url.contains("cfd_tunnel"), client.sent[0].url)
    }

    @Test
    fun `a missing tunnel is created with its configuration held at Cloudflare`() = runTest {
        val (provider, client) = provider(listOf(ok("[]"), ok("""{"id":"tun-2"}""")))

        assertEquals("tun-2", provider.findOrCreateTunnel("gryonixnexus-example-com"))

        val create = client.sent.last()
        assertEquals("POST", create.method)
        val body = assertNotNull(client.lastBody())
        assertEquals("gryonixnexus-example-com", body["name"]?.jsonPrimitive?.content)
        assertEquals("cloudflare", body["config_src"]?.jsonPrimitive?.content)
    }

    @Test
    fun `a tunnel with another name is not adopted`() = runTest {
        val listing = """[{"id":"someone-elses","name":"unrelated"}]"""
        val (provider, client) = provider(listOf(ok(listing), ok("""{"id":"tun-3"}""")))

        assertEquals("tun-3", provider.findOrCreateTunnel("gryonixnexus-example-com"))
        assertEquals("POST", client.sent.last().method)
    }

    // ------------------------------------------------------------- Ingress

    @Test
    fun `every route ends at Caddy and the list ends in a catch-all`() = runTest {
        val (provider, client) = provider(listOf(ok("{}")))

        provider.applyIngress(
            "tun-1",
            listOf(
                TunnelRoute("vault.example.com"),
                TunnelRoute("cloud.example.com"),
            ),
        )

        val put = client.sent.last()
        assertEquals("PUT", put.method)
        val config = assertNotNull(client.lastBody()?.get("config") as? JsonObject)
        val ingress = assertNotNull(config["ingress"] as? JsonArray).map { it as JsonObject }
        assertEquals(3, ingress.size, "expected two names plus the catch-all")

        assertEquals("vault.example.com", ingress[0]["hostname"]?.jsonPrimitive?.content)
        assertEquals("https://127.0.0.1:443", ingress[0]["service"]?.jsonPrimitive?.content)
        val origin = assertNotNull(ingress[0]["originRequest"] as? JsonObject)
        assertEquals(true, origin["noTLSVerify"]?.jsonPrimitive?.booleanOrNull)
        assertEquals("vault.example.com", origin["originServerName"]?.jsonPrimitive?.content)
        assertNull(ingress[2]["hostname"])
        assertEquals("http_status:404", ingress[2]["service"]?.jsonPrimitive?.content)
    }

    // ----------------------------------------------------------- The names

    @Test
    fun `tunnel hostnames are proxied unlike every other record this app writes`() = runTest {
        val zone = """[{"id":"zone-1","name":"example.com"}]"""
        val (provider, client) = provider(listOf(ok(zone), ok("[]"), ok("{}")))

        provider.publishHostnames(listOf("vault.example.com"), "tun-1", "example.com")

        val create = client.sent.last()
        assertEquals("POST", create.method)
        val body = assertNotNull(client.lastBody())
        assertEquals("CNAME", body["type"]?.jsonPrimitive?.content)
        assertEquals("tun-1.cfargotunnel.com", body["content"]?.jsonPrimitive?.content)
        assertEquals(true, body["proxied"]?.jsonPrimitive?.booleanOrNull)
    }

    /** Republishing must update in place */
    @Test
    fun `an existing hostname is updated rather than added twice`() = runTest {
        val zone = """[{"id":"zone-1","name":"example.com"}]"""
        val existing = """
            [{"id":"rec-1","type":"CNAME","name":"vault.example.com","content":"old.cfargotunnel.com"}]
        """.trimIndent()
        val (provider, client) = provider(listOf(ok(zone), ok(existing), ok("{}")))

        provider.publishHostnames(listOf("vault.example.com"), "tun-9", "example.com")

        val update = client.sent.last()
        assertEquals("PUT", update.method)
        assertTrue(update.url.endsWith("/dns_records/rec-1"), update.url)
        assertEquals("tun-9.cfargotunnel.com", client.lastBody()?.get("content")?.jsonPrimitive?.content)
    }

    /** Address records for the name would block the CNAME */
    @Test
    fun `address records for the name make way for the tunnel`() = runTest {
        val zone = """[{"id":"zone-1","name":"example.com"}]"""
        val existing = """
            [{"id":"rec-a","type":"A","name":"vault.example.com","content":"203.0.113.9"},
             {"id":"rec-mx","type":"MX","name":"vault.example.com","content":"mail.example.com"}]
        """.trimIndent()
        val (provider, client) = provider(listOf(ok(zone), ok(existing), ok("{}"), ok("{}")))

        provider.publishHostnames(listOf("vault.example.com"), "tun-1", "example.com")

        assertTrue(client.sent[1].url.contains("name=vault.example.com"), client.sent[1].url)
        assertEquals("DELETE", client.sent[2].method)
        assertTrue(client.sent[2].url.endsWith("/dns_records/rec-a"), client.sent[2].url)
        assertEquals("POST", client.sent[3].method)
        assertEquals(4, client.sent.size, "the MX record stays")
    }

    // ------------------------------------------------ Discovery and refusals

    @Test
    fun `the account id is read off a zone`() = runTest {
        val zones = """
            [{"id":"zone-1","name":"example.com","account":{"id":"acc-42","name":"Owner"}}]
        """.trimIndent()
        val client = StubCloudflareClient(listOf(ok(zones)))

        assertEquals("acc-42", CloudflareTunnelProvider.accountID("t", client, base))
    }

    @Test
    fun `an account-level refusal carries Cloudflare's own words`() = runTest {
        val denied = """
            {"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"result":null}
        """.trimIndent()
        val (provider, _) = provider(listOf(denied to 403))

        // 403 maps to the token case: the one thing the owner can fix.
        assertEquals(
            CloudflareError.InvalidToken,
            runCatching { provider.findOrCreateTunnel("x") }.exceptionOrNull(),
        )
    }

    /**
     * Not in the Swift twin. The connector token IS the tunnel's whole
     * authority, and the endpoint answers with a bare JSON string rather than an
     * object — a reader that expected an object would find nothing and report
     * success with an empty credential, which reaches the server as a connector
     * that never authenticates.
     */
    @Test
    fun `the connector token comes back as the bare string the endpoint sends`() = runTest {
        val (provider, client) = provider(listOf(ok("\"eyJhIjoiYiJ9\"")))

        assertEquals("eyJhIjoiYiJ9", provider.connectorToken("tun-1"))
        assertEquals("$base/accounts/$account/cfd_tunnel/tun-1/token", client.sent.last().url)
    }

    @Test
    fun `a tunnel that answers with no token is a failure rather than an empty one`() = runTest {
        val (provider, _) = provider(listOf(ok("null")))

        val error = runCatching { provider.connectorToken("tun-1") }.exceptionOrNull()
        assertTrue(error is CloudflareError.Api, "got $error")
        assertTrue(error.message.contains("no connector token"), error.message)
    }

    @Test
    fun `deleting a tunnel addresses it by id under the account`() = runTest {
        val (provider, client) = provider(listOf(ok("{}")))

        provider.deleteTunnel("tun-1")

        assertEquals("DELETE", client.sent.last().method)
        assertEquals("$base/accounts/$account/cfd_tunnel/tun-1", client.sent.last().url)
    }
}

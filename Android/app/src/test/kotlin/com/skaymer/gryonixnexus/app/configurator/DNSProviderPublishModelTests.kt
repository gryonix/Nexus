package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.app.secrets.DNSCredentials
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.core.CloudflareDNSProvider
import com.skaymer.gryonixnexus.core.CloudflareHTTPClient
import com.skaymer.gryonixnexus.core.CloudflareRequest
import com.skaymer.gryonixnexus.core.CloudflareResponse
import com.skaymer.gryonixnexus.core.DNSRecord
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class DNSProviderPublishModelTests {
    private val base = "https://api.example.test/client/v4"

    private class FakeClient(responses: List<Pair<String, Int>>) : CloudflareHTTPClient {
        private val queue = ArrayDeque(responses.map { CloudflareResponse(it.first, it.second) })
        val sent = mutableListOf<CloudflareRequest>()
        override suspend fun send(request: CloudflareRequest): CloudflareResponse {
            sent += request
            return queue.removeFirstOrNull() ?: CloudflareResponse("{}", 500)
        }
    }

    private fun ok(result: String): Pair<String, Int> =
        """{"success":true,"errors":[],"result":$result}""" to 200

    private fun rejected(code: Int, message: String, status: Int): Pair<String, Int> =
        """{"success":false,"errors":[{"code":$code,"message":"$message"}],"result":null}""" to status

    private fun zone(domain: String = "example.com", records: List<DNSRecord> = listOf(
        DNSRecord(name = "mail.$domain", type = DNSRecord.RecordType.A, value = "203.0.113.4"),
    )) = ConfigurationExport.DNSZone(domain = domain, records = records, copyText = "", zoneFile = null, csvFile = null)

    private fun credentials(secrets: InMemorySecretStore = InMemorySecretStore()) =
        DNSCredentials(InMemorySettingsStore(), secrets) to DNSCredentialTokenStore(secrets)

    private fun model(
        responses: List<Pair<String, Int>>,
        pair: Pair<DNSCredentials, DNSCredentialTokenStore> = credentials(),
    ): Triple<DNSProviderPublishModel, DNSCredentialTokenStore, FakeClient> {
        val client = FakeClient(responses)
        val publish = DNSProviderPublishModel(
            pair.first,
            pair.second,
        ) { _, token -> CloudflareDNSProvider(token, client, base) }
        return Triple(publish, pair.second, client)
    }

    // ------------------------------------------------------------- Gating

    @Test
    fun `publish is disabled while empty, working, or with nothing to publish`() {
        assertFalse(DNSProviderPublishModel.canPublish("", isWorking = false, hasZones = true))
        assertFalse(DNSProviderPublishModel.canPublish("token", isWorking = true, hasZones = true))
        assertFalse(DNSProviderPublishModel.canPublish("token", isWorking = false, hasZones = false))
        assertTrue(DNSProviderPublishModel.canPublish("token", isWorking = false, hasZones = true))
    }

    // ---------------------------------------------------------- Account switch

    @Test
    fun `switching tokens never carries the previous one over`() {
        val (credentials, tokens) = credentials()
        val first = credentials.add("Home", DNSProviderKind.CLOUDFLARE)
        val second = credentials.add("Work", DNSProviderKind.CLOUDFLARE)
        tokens.setToken(first, "first-token")

        val (publish, _, _) = model(emptyList(), credentials to tokens)
        publish.loadStoredToken()
        assertEquals("first-token", publish.state.value.token)

        publish.loadToken(second.id)
        assertEquals(second.id, publish.state.value.credentialID)
        assertEquals("", publish.state.value.token)

        tokens.setToken(second, "second-token")
        publish.loadToken(second.id)
        assertEquals("second-token", publish.state.value.token)
    }

    @Test
    fun `switching providers shows that provider's own saved tokens`() {
        val (credentials, tokens) = credentials()
        val cloudflare = credentials.add("Home", DNSProviderKind.CLOUDFLARE)
        val hetzner = credentials.add("Rack", DNSProviderKind.HETZNER)
        tokens.setToken(cloudflare, "cloudflare-token")
        tokens.setToken(hetzner, "hetzner-token")

        val (publish, _, _) = model(emptyList(), credentials to tokens)
        publish.loadStoredToken()
        assertEquals("cloudflare-token", publish.state.value.token)

        publish.selectProvider(DNSProviderKind.HETZNER)
        assertEquals(listOf(hetzner.id), publish.state.value.saved.map { it.id })
        assertEquals("hetzner-token", publish.state.value.token)

        publish.selectProvider(DNSProviderKind.PORKBUN)
        assertTrue(publish.state.value.saved.isEmpty())
        assertEquals("", publish.state.value.token)
    }

    @Test
    fun `loading the stored token again does not overwrite what was typed`() {
        val (credentials, tokens) = credentials()
        tokens.setToken(credentials.add("Home", DNSProviderKind.CLOUDFLARE), "stored-token")
        val (publish, _, _) = model(emptyList(), credentials to tokens)

        publish.setToken("typed-instead")
        publish.loadStoredToken()
        assertEquals("typed-instead", publish.state.value.token)
    }

    // --------------------------------------------------------------- Publish

    @Test
    fun `publish verifies the token, saves it only after, then creates a missing record`() = runTest {
        val (publish, cloudflare, client) = model(
            listOf(
                ok("{}"),
                ok("""[{"id":"zone123","name":"example.com"}]"""),
                ok("[]"),
                ok("{}"),
            ),
        )
        publish.setToken("good-token")

        publish.publish(listOf(zone()))

        val state = publish.state.value
        assertFalse(state.isWorking)
        assertFalse(state.failed)
        assertEquals(listOf("example.com: 1 added, 0 updated, 0 already correct."), state.lines)
        // **A token typed in the wizard joins the list in Settings**: there
        // was no credential for this provider, so publishing made one.
        val saved = state.saved.single { it.id == state.credentialID }
        assertEquals("good-token", cloudflare.token(saved))
        assertEquals(4, client.sent.size)
        assertEquals("POST", client.sent.last().method)
    }

    /**
     * **A token that was never good has no business sitting in the keystore
     * waiting to fail again next time.** Verify runs first and writes
     * nothing; a bad token must leave the store exactly as it found it.
     */
    @Test
    fun `an invalid token is never stored, and nothing is applied`() = runTest {
        val (publish, cloudflare, client) = model(listOf(rejected(1000, "Invalid API Token", 401)))
        publish.setToken("bad-token")

        publish.publish(listOf(zone()))

        val state = publish.state.value
        assertFalse(state.isWorking)
        assertTrue(state.failed)
        assertTrue(state.saved.none { cloudflare.token(it) != null })
        // Only the verify call went out — a failed verify must not reach the
        // zone lookup or touch a single record.
        assertEquals(1, client.sent.size)
    }

    /**
     * **One zone failing does not cancel the others** — a deployment can span
     * domains that live in different accounts entirely, and the summary line
     * from the zone that DID work must still be there.
     */
    @Test
    fun `a zone whose domain cannot be found does not stop the next zone`() = runTest {
        val (publish, _, _) = model(
            listOf(
                ok("{}"),
                // "second.test" — no matching zone in the lookup result.
                ok("[]"),
                // "first.test" — resolves and creates cleanly.
                ok("""[{"id":"zone1","name":"first.test"}]"""),
                ok("[]"),
                ok("{}"),
            ),
        )
        publish.setToken("good-token")

        publish.publish(listOf(zone(domain = "second.test"), zone(domain = "first.test")))

        val state = publish.state.value
        assertTrue(state.failed)
        assertTrue(state.lines.any { it.startsWith("second.test:") })
        assertTrue(state.lines.contains("first.test: 1 added, 0 updated, 0 already correct."))
    }
}

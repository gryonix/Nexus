package com.skaymer.gryonixnexus.app.licensing

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.util.Base64
import kotlinx.coroutines.runBlocking
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.junit.jupiter.api.Test

/** Tokens signed with a throwaway key. */
class LicenseTest {
    private val signer = Ed25519PrivateKeyParameters(ByteArray(32) { 7 }, 0)
    private val key = Base64.getEncoder().encodeToString(signer.generatePublicKey().encoded)
    private val device = "5A1F3C2E-0000-4000-8000-000000000001"
    private val now = 1_800_000_000L
    private val monthEnd = 1_802_851_200L

    private fun token(product: String? = "nexus", plan: String = "monthly", expires: Long? = monthEnd): String {
        val fields = buildList {
            add("\"dev\":\"$device\"")
            add("\"iat\":1800000000")
            add("\"lic\":\"0123456789abcdef\"")
            add("\"plan\":\"$plan\"")
            add("\"v\":1")
            expires?.let { add("\"exp\":$it") }
            product?.let { add("\"prod\":\"$it\"") }
        }.sorted()
        val data = "{${fields.joinToString(",")}}".toByteArray()
        val signature = Ed25519Signer().run {
            init(true, signer)
            update(data, 0, data.size)
            generateSignature()
        }
        val encoder = Base64.getUrlEncoder().withoutPadding()
        return "${encoder.encodeToString(data)}.${encoder.encodeToString(signature)}"
    }

    private val subscription get() = token()
    private val lifetime get() = token(plan = "lifetime", expires = null)
    private val code = "ABCDE-FGHJK-MNPQR-STVWX"

    private class FakeApi(val grant: LicenseGrant?, val failure: LicenseFailure? = null) : LicenseApi() {
        override suspend fun activate(code: String, device: String, name: String): LicenseGrant {
            failure?.let { throw LicenseApiException(it) }
            return grant!!
        }
        override suspend fun deactivate(code: String, device: String) {}

        val marked = mutableListOf<Pair<String, String>>()
        var markOffline = false

        override suspend fun markUsed(code: String, device: String) {
            if (markOffline) throw LicenseApiException(LicenseFailure.OFFLINE)
            marked += code to device
        }
    }

    private fun store(api: LicenseApi, secrets: InMemorySecretStore = InMemorySecretStore(), at: Long = now) =
        LicenseStore(secrets, { device }, api = api, publicKey = key, clock = { at })

    private val realServer = Deployment(
        id = "S-1",
        name = "example.net",
        topology = Topology.SINGLE_HOST,
        domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
    )

    @Test
    fun `a subscription token carries its plan and end`() {
        val token = LicenseTokens.verify(subscription, device, now, key)
        assertEquals(LicensePlan.MONTHLY, token.plan)
        assertEquals(1_802_851_200L, token.expires)
    }

    @Test
    fun `a lifetime token never expires`() {
        val token = LicenseTokens.verify(lifetime, device, 4_000_000_000L, key)
        assertEquals(LicensePlan.LIFETIME, token.plan)
        assertNull(token.expires)
    }

    @Test
    fun `a bundle opens this app and a vpn license does not`() {
        assertEquals(LicenseProduct.BUNDLE, LicenseTokens.verify(token(product = "bundle"), device, now, key).product)
        assertFailsWith<LicenseTokenError.OtherProduct> {
            LicenseTokens.verify(token(product = "vpn"), device, now, key)
        }
        assertFailsWith<LicenseTokenError.Malformed> {
            LicenseTokens.verify(token(product = null), device, now, key)
        }
    }

    @Test
    fun `a grant for the other app is refused even if the server sent it`() = runBlocking {
        val license = store(FakeApi(LicenseGrant(token(product = "vpn"), code)))
        assertEquals(LicenseFailure.WRONG_PRODUCT, license.activate(code))
        assertEquals(LicenseStatus.Demo, license.status.value)
    }

    @Test
    fun `the first generation marks the license used, and a missing connection only delays it`() = runBlocking {
        val api = FakeApi(LicenseGrant(lifetime, code))
        val license = store(api)
        license.activate(code)

        api.markOffline = true
        license.noteFirstGeneration()
        assertTrue(api.marked.isEmpty())

        api.markOffline = false
        license.refreshIfDue()
        assertEquals(listOf(code to device), api.marked)

        license.noteFirstGeneration()
        license.refreshIfDue()
        assertEquals(1, api.marked.size)
    }

    @Test
    fun `a token is refused after its end, on another device, or with another key`() {
        assertFailsWith<LicenseTokenError.Expired> { LicenseTokens.verify(subscription, device, 1_802_851_201L, key) }
        assertFailsWith<LicenseTokenError.OtherDevice> {
            LicenseTokens.verify(lifetime, "5A1F3C2E-0000-4000-8000-000000000002", now, key)
        }
        assertFailsWith<LicenseTokenError.BadSignature> { LicenseTokens.verify(lifetime, device, now) }
    }

    @Test
    fun `codes are normalised like the server does`() {
        assertEquals("ABCDE-FGHJK-MNPQR-STVWX", ActivationCode.normalize("abcde fghjk mnpqr stvwx"))
        assertEquals("00000-11111-11111-00000", ActivationCode.normalize("OOOOO-IIIII-LLLLL-00000"))
        assertNull(ActivationCode.normalize("UUUUU-UUUUU-UUUUU-UUUUU"))
    }

    @Test
    fun `activating unlocks real servers and survives a restart`() = runBlocking {
        val secrets = InMemorySecretStore()
        val license = store(FakeApi(LicenseGrant(lifetime, code)), secrets)
        assertEquals(LicenseStatus.Demo, license.status.value)
        assertFailsWith<LicenseLockedException> { LicenseGate.check(realServer) }
        assertNull(license.activate(code))
        assertEquals(LicenseStatus.Active(LicensePlan.LIFETIME, null), store(FakeApi(null), secrets).status.value)
        LicenseGate.check(realServer)
    }

    @Test
    fun `an ended subscription reads as expired, not demo`() = runBlocking {
        val secrets = InMemorySecretStore()
        store(FakeApi(LicenseGrant(subscription, code)), secrets).activate(code)
        val later = store(FakeApi(null, LicenseFailure.EXPIRED), secrets, at = 1_802_851_201L)
        assertEquals(LicenseStatus.Expired, later.status.value)
        val locked = assertFailsWith<LicenseLockedException> { LicenseGate.check(realServer) }
        assertTrue(locked.renew)
    }

    @Test
    fun `server refusals come back as failures and change nothing`() = runBlocking {
        val license = store(FakeApi(null, LicenseFailure.DEVICE_LIMIT))
        assertEquals(LicenseFailure.DEVICE_LIMIT, license.activate(code))
        assertEquals(LicenseFailure.UNKNOWN_CODE, license.activate("short"))
        assertEquals(LicenseStatus.Demo, license.status.value)
    }

    @Test
    fun `demo servers pass the gate while locked`() {
        store(FakeApi(null))
        DemoDeployments.fleet(2).forEach { LicenseGate.check(it) }
    }

    @Test
    fun `the prompt lets demo servers through and raises the lock for real ones`() {
        LicenseGate.unlocked = false
        LicensePrompt.showing.value = false
        assertTrue(LicensePrompt.allow(DemoDeployments.fleet(1).first().id))
        assertEquals(false, LicensePrompt.showing.value)
        assertEquals(false, LicensePrompt.allow(realServer))
        assertTrue(LicensePrompt.showing.value)
        LicensePrompt.showing.value = false
    }
}

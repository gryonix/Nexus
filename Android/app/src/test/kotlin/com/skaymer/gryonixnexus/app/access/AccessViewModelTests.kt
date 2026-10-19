package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.agentcontrol.AgentVaultOperations
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The sign-in details screen */
class AccessViewModelTests {
    private val secrets = InMemorySecretStore()

    private val server = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
    )

    private val report: String =
        checkNotNull(javaClass.getResourceAsStream("/install-report-single.txt"))
            .bufferedReader().readText()

    private fun model(scope: CoroutineScope) = AccessViewModel(
        scope = scope,
        reports = { InstallReportStore(secrets, it.id) },
        credentials = { AccessCredentialStore(secrets, it.id) },
    )

    private class RefusingTransport(
        private val error: Throwable,
        /** Paths to refuse; everything else is "nothing scripted" */
        private val paths: List<String> = listOf("/gryonixnexusd.v1.Vault/"),
    ) : AgentTransport {
        override suspend fun unary(path: String, request: ByteArray): ByteArray =
            if (paths.any { path.contains(it) }) throw error
            else throw AgentError.Transport("nothing scripted for $path")

        override fun serverStream(path: String, request: ByteArray) = emptyFlow<ByteArray>()
    }

    private fun vaultModel(scope: CoroutineScope, transport: AgentTransport) = AccessViewModel(
        scope = scope,
        reports = { InstallReportStore(secrets, it.id) },
        credentials = { AccessCredentialStore(secrets, it.id) },
        vault = { AgentVaultOperations(AgentClient(transport)) },
    )

    private val signedOutRefusal = AgentError.Rpc(
        "unauthenticated",
        "session_expired: this device's session has run out — sign in again to keep using this server",
    )

    private val unidentifiedRefusal = AgentError.Rpc(
        "unauthenticated",
        "device_unidentified: this server signs devices out on a schedule, and this " +
            "client did not say which device it is — update the app",
    )

    private fun signedOutModel(scope: CoroutineScope) =
        vaultModel(scope, RefusingTransport(signedOutRefusal))

    private fun unidentifiedModel(scope: CoroutineScope) =
        vaultModel(scope, RefusingTransport(unidentifiedRefusal))

    private fun failingModel(scope: CoroutineScope, error: Throwable) =
        vaultModel(scope, RefusingTransport(error))

    private fun failingOnSaveModel(scope: CoroutineScope) = vaultModel(
        scope,
        RefusingTransport(
            signedOutRefusal,
            paths = listOf("/gryonixnexusd.v1.Vault/PutVaultEntries"),
        ),
    )

    private fun store() = InstallReportStore(secrets, server.id)

    private fun overrides() = AccessCredentialStore(secrets, server.id)

    @Test
    fun `the report becomes one card per web login`() = runTest(StandardTestDispatcher()) {
        store().save("single", report)
        val access = model(this)
        access.load(server)
        runCurrent()
        assertEquals(
            listOf("Vaultwarden", "Nextcloud", "AdGuard Home", "VPN Panel"),
            access.state.value.accounts.map { it.title }
        )
        val nextcloud = access.state.value.accounts.first { it.title == "Nextcloud" }
        assertEquals("admin", nextcloud.login)
        assertEquals("nc-Pw-92kd", nextcloud.password)
        assertTrue(access.state.value.accounts.first().isVaultwarden)
    }

    @Test
    fun `an absent report and a report without logins are told apart`() =
        runTest(StandardTestDispatcher()) {
            val empty = model(this)
            empty.load(server)
            runCurrent()
            assertTrue(empty.state.value.saysThereIsNoReport)
            assertFalse(empty.state.value.saysThereAreNoLogins)

            store().save("single", "WireGuard client:\n  Configuration: ss://not-a-site\n")
            val noLogins = model(this)
            noLogins.load(server)
            runCurrent()
            assertFalse(noLogins.state.value.saysThereIsNoReport)
            assertTrue(noLogins.state.value.saysThereAreNoLogins)
        }

    @Test
    fun `nothing is claimed before the storage has answered`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val access = model(this)
            access.load(server)
            assertTrue(access.state.value.isLoading)
            assertFalse(access.state.value.saysThereIsNoReport)
            assertFalse(access.state.value.saysThereAreNoLogins)
            runCurrent()
        }

    /** Only a GENUINE change is stored */
    @Test
    fun `saving stores the edited field and not the untouched one`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val access = model(this)
            access.load(server)
            runCurrent()
            val id = access.state.value.accounts.first { it.title == "Nextcloud" }.id
            access.editPassword(id, "changedOnTheSite")
            access.save(server)
            runCurrent()

            val stored = overrides().load()
            assertEquals(1, stored.size)
            assertEquals("changedOnTheSite", stored[id]?.password)
            assertNull(stored[id]?.login)
        }

    @Test
    fun `editing a field back to what the report said stores nothing`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val access = model(this)
            access.load(server)
            runCurrent()
            val id = access.state.value.accounts.first { it.title == "Nextcloud" }.id
            access.editPassword(id, "changed")
            access.editPassword(id, "nc-Pw-92kd")
            access.save(server)
            runCurrent()
            assertTrue(overrides().load().isEmpty())
        }

    @Test
    fun `a stored override is what the card shows`() = runTest(StandardTestDispatcher()) {
        store().save("single", report)
        overrides().save(
            mapOf(AccessCredentialStore.key("single", "Nextcloud") to
                AccessCredential(password = "mine"))
        )
        val access = model(this)
        access.load(server)
        runCurrent()
        val card = access.state.value.accounts.first { it.title == "Nextcloud" }
        assertEquals("mine", card.password)
        assertEquals("nc-Pw-92kd", card.reportPassword)
    }

    @Test
    fun `an override brings a token field to a card that had none`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", "Homepage: https://home.example.test\n  Administrator: me\n")
            overrides().save(
                mapOf(AccessCredentialStore.key("single", "Homepage") to
                    AccessCredential(token = "recorded"))
            )
            val access = model(this)
            access.load(server)
            runCurrent()
            assertTrue(access.state.value.accounts.single().hasToken)
        }

    /** Nothing is bared by default, and revealing is per FIELD */
    @Test
    fun `revealing one field leaves the others hidden`() = runTest(StandardTestDispatcher()) {
        store().save("single", report)
        val access = model(this)
        access.load(server)
        runCurrent()
        assertTrue(access.state.value.revealed.isEmpty())
        access.reveal("a")
        assertEquals(setOf("a"), access.state.value.revealed)
        access.hide("a")
        assertTrue(access.state.value.revealed.isEmpty())
    }

    @Test
    fun `an edit takes the saved confirmation back`() = runTest(StandardTestDispatcher()) {
        store().save("single", report)
        val access = model(this)
        access.load(server)
        runCurrent()
        val id = access.state.value.accounts.first().id
        access.save(server)
        runCurrent()
        assertTrue(access.state.value.justSaved)
        access.editLogin(id, "someone")
        assertFalse(access.state.value.justSaved)
    }

    /** Closing the sheet empties it */
    @Test
    fun `resetting forgets the accounts and what was revealed`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val access = model(this)
            access.load(server)
            runCurrent()
            access.reveal("a")
            access.reset()
            assertTrue(access.state.value.accounts.isEmpty())
            assertTrue(access.state.value.revealed.isEmpty())
            assertTrue(access.state.value.isLoading)
        }

    // ------------------------------------------------- the server signs us out

    @Test
    fun `being signed out clears what this device cached`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            overrides().save(mapOf("nextcloud" to AccessCredential(password = "typed-here")))
            val access = signedOutModel(this)
            access.load(server)
            runCurrent()

            assertEquals(AccessSync.SignedOut, access.state.value.sync)
            assertTrue(access.state.value.accounts.isEmpty(), "the cards are gone")
            assertFalse(access.state.value.hasReport, "and the screen no longer claims a report")
            assertTrue(store().load().isEmpty(), "the stored report is gone from the keystore")
            assertTrue(overrides().load().isEmpty(), "and so are the edits made on this device")
        }

    /** Any OTHER refusal leaves everything where it is */
    @Test
    fun `a refusal that is not a sign-out keeps the cards and the stores`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val access = failingModel(this, AgentError.Transport("connection refused"))
            access.load(server)
            runCurrent()

            assertTrue(access.state.value.sync is AccessSync.Failed)
            assertFalse(access.state.value.accounts.isEmpty(), "the cards are still there")
            assertFalse(store().load().isEmpty(), "and so is the report they came from")
        }

    @Test
    fun `a device the server cannot identify keeps everything it cached`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            overrides().save(mapOf("nextcloud" to AccessCredential(password = "typed-here")))
            val access = unidentifiedModel(this)
            access.load(server)
            runCurrent()

            assertEquals(AccessSync.Unidentified, access.state.value.sync)
            assertFalse(access.state.value.accounts.isEmpty(), "the cards are still there")
            assertFalse(store().load().isEmpty(), "the stored report is still in the keystore")
            assertFalse(overrides().load().isEmpty(), "and so are the edits made on this device")
        }

    @Test
    fun `a save refused by a server that signed us out keeps what was typed`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val access = failingOnSaveModel(this)
            access.load(server)
            runCurrent()
            val nextcloud = access.state.value.accounts.first { it.title == "Nextcloud" }
            access.editPassword(nextcloud.id, "typed-just-now")
            access.save(server)
            runCurrent()

            assertTrue(access.state.value.sync is AccessSync.Failed,
                       "the person is told it did not reach the server")
            assertEquals(
                "typed-just-now",
                access.state.value.accounts.first { it.title == "Nextcloud" }.password,
                "and what they typed is still on screen",
            )
            assertFalse(overrides().load().isEmpty(), "and saved on this device")
        }

    @Test
    fun `the host is named only when a deployment has two of them`() =
        runTest(StandardTestDispatcher()) {
            store().save("single", report)
            val one = model(this)
            one.load(server)
            runCurrent()
            assertFalse(one.showsHost)

            store().save("home", report)
            val two = model(this)
            two.load(server)
            runCurrent()
            assertTrue(two.showsHost)
        }

    @Test
    fun `a machine of the node list is named the way it is named elsewhere`() {
        val relay = DeploymentNode(
            id = "N-9",
            name = "",
            endpoint = HostEndpoint(host = "198.51.100.7", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        val fleet = server.copy(storedNodes = listOf(relay))
        assertEquals(AccessHostTitle.VPS, AccessHostTitle.of(fleet, "vps"))
        assertEquals(AccessHostTitle.LocalServer, AccessHostTitle.of(fleet, "home"))
        assertEquals(AccessHostTitle.Server, AccessHostTitle.of(fleet, "single"))
        assertEquals(AccessHostTitle.Named("198.51.100.7"), AccessHostTitle.of(fleet, "N-9"))
        assertEquals(
            AccessHostTitle.Named("relay"),
            AccessHostTitle.of(fleet.copy(storedNodes = listOf(relay.copy(name = "relay"))), "N-9")
        )
        assertEquals(AccessHostTitle.Server, AccessHostTitle.of(fleet, "N-404"))
    }
}

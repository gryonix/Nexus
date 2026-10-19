package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.access.AccessCredential
import com.skaymer.gryonixnexus.app.access.AccessCredentialStore
import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Moving one server to another device */
class DeploymentTransferTests {
    /** Base64 without android.util, which throws under a unit test */
    private object JvmBase64 : DeploymentTransferService.Base64Codec {
        override fun encode(bytes: ByteArray): String =
            java.util.Base64.getEncoder().encodeToString(bytes)

        override fun decode(text: String): ByteArray? =
            runCatching { java.util.Base64.getDecoder().decode(text) }.getOrNull()
    }

    private fun server(id: String = "alpha") = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "$id.test",
        entry = HostEndpoint(host = "203.0.113.1", user = "root"),
    )

    private fun service(
        secrets: InMemorySecretStore = InMemorySecretStore(),
        store: InMemoryDeploymentStore = InMemoryDeploymentStore(),
    ) = Triple(
        DeploymentTransferService(secrets, store, JvmBase64), secrets, store,
    )

    @Test
    fun `a file with a one-time key does not carry the long-lived key`() {
        val (export, secrets, _) = service()
        val deployment = server()
        DeploymentSecrets(secrets, deployment.id).setIdentitySeed(ByteArray(32) { 7 })
        val oneTime = TransferKey(ByteArray(32) { 9 }, "ab12")

        val bundle = export.export(deployment, oneTime)
        assertEquals(java.util.Base64.getEncoder().encodeToString(ByteArray(32) { 9 }), bundle.sshIdentitySeed)
        assertEquals("ab12", bundle.sshTransferID)

        val (import, fresh, _) = service()
        import.apply(export.decode(export.encode(bundle)))
        val restored = DeploymentSecrets(fresh, deployment.id)
        assertEquals("ab12", restored.pendingTransferID())
        assertEquals(ByteArray(32) { 9 }.toList(), restored.identitySeed()?.toList())
        restored.clearPendingTransfer()
        assertNull(restored.pendingTransferID())
    }

    @Test
    fun `the bundle carries the key, the password, the pin and the report`() {
        val (export, secrets, _) = service()
        val deployment = server()
        val id = deployment.id
        val mine = DeploymentSecrets(secrets, id)
        mine.setIdentitySeed(ByteArray(32) { it.toByte() })
        mine.setPassword("hunter2", deployment.nodes.single().sshHost)
        mine.setHostKeyPin("SHA256:abc", deployment.nodes.single().legacySlot!!)
        InstallReportStore(secrets, id) { 1_700_000_000_000 }.save("single", "PASSWORDS")
        AccessCredentialStore(secrets, id).save(
            mapOf(AccessCredentialStore.key("single", "Nextcloud") to AccessCredential(login = "me")),
        )

        val bundle = export.export(deployment)
        assertEquals(1, bundle.version)
        assertEquals(
            java.util.Base64.getEncoder().encodeToString(ByteArray(32) { it.toByte() }),
            bundle.sshIdentitySeed,
        )
        assertEquals(mapOf("vps" to "hunter2"), bundle.dashboardPasswords)
        assertEquals("hunter2", bundle.dashboardPassword)
        assertEquals(mapOf("vps" to "SHA256:abc"), bundle.hostKeyPins)
        assertEquals("PASSWORDS", bundle.reports.single().text)
        assertEquals("me", bundle.accessCredentials?.values?.single()?.login)

        // Restored on a device that has never seen this server.
        val (import, fresh, store) = service()
        import.apply(export.decode(export.encode(bundle)))
        val restored = DeploymentSecrets(fresh, id)
        assertEquals("hunter2", restored.password(deployment.nodes.single().sshHost))
        assertEquals("SHA256:abc", restored.hostKeyPin(deployment.nodes.single().legacySlot!!))
        assertEquals(32, restored.identitySeed()?.size)
        assertEquals("PASSWORDS", InstallReportStore(fresh, id).load().single().text)
        assertEquals(id, store.load().single().id)
    }

    @Test
    fun `a report keeps its date across the two epochs`() {
        val (export, secrets, _) = service()
        val deployment = server()
        val saved = 1_700_000_000_000L
        InstallReportStore(secrets, deployment.id) { saved }.save("single", "text")

        val bundle = export.export(deployment)
        assertEquals(saved / 1000.0 - 978_307_200.0, bundle.reports.single().savedAt, 0.001)
        assertEquals(saved, TransferTime.fromApple(bundle.reports.single().savedAt))
        assertTrue(bundle.reports.single().savedAt < saved / 1000.0)
    }

    @Test
    fun `the file names its fields the way the other app spells them`() {
        val (export, secrets, _) = service()
        val deployment = server()
        DeploymentSecrets(secrets, deployment.id)
            .setPassword("p", deployment.nodes.single().sshHost)
        val text = export.encode(export.export(deployment))
        for (key in listOf(
            "\"version\"", "\"deployment\"", "\"dashboardPassword\"",
            "\"dashboardPasswords\"", "\"hostKeyPins\"", "\"reports\"",
            "\"wireGuardSeeds\"",
        )) {
            assertTrue(text.contains(key), "the bundle is missing $key")
        }
    }

    @Test
    fun `an older bundle's single password covers every machine`() {
        val deployment = server()
        val (import, secrets, _) = service()
        val bundle = DeploymentTransfer(deployment = deployment, dashboardPassword = "old")
        import.apply(bundle)
        for (node in deployment.nodes) {
            assertEquals("old", DeploymentSecrets(secrets, deployment.id).password(node.sshHost))
        }
    }

    @Test
    fun `a bundle without logins leaves the ones already on this device alone`() {
        val deployment = server()
        val (import, secrets, _) = service()
        val store = AccessCredentialStore(secrets, deployment.id)
        store.save(mapOf("single|Nextcloud" to AccessCredential(password = "mine")))

        import.apply(DeploymentTransfer(deployment = deployment))

        assertEquals("mine", store.load()["single|Nextcloud"]?.password)
    }

    @Test
    fun `a file from a newer app is refused rather than half read`() {
        val (service, _, _) = service()
        val text = service.encode(
            DeploymentTransfer(version = 2, deployment = server()),
        )
        assertFailsWith<DeploymentTransferService.UnsupportedVersion> { service.decode(text) }
    }

    @Test
    fun `the file is named after the domain, and never after nothing`() {
        assertEquals("alpha.test.gryonixserver", DeploymentTransferService.fileName(server()))
        val unnamed = server().copy(domain = "", name = "")
        assertEquals("server.gryonixserver", DeploymentTransferService.fileName(unnamed))
        // A domain cannot become a path.
        val slashed = server().copy(domain = "a/b")
        assertEquals("a-b.gryonixserver", DeploymentTransferService.fileName(slashed))
        assertNull(DeploymentTransferService.fileName(server()).firstOrNull { it == '/' })
    }
}

package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.HostKeyPinAccounts
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class DeploymentSecretsTests {
    private val id = "9F1C4C2E-0000-0000-0000-000000000001"
    private val store = InMemorySecretStore()
    private val secrets = DeploymentSecrets(store, id)

    /** The literal name, because the literal name is the contract */
    @Test
    fun `the identity seed lives under the name the other app writes`() {
        val seed = ByteArray(32) { it.toByte() }
        secrets.setIdentitySeed(seed)

        assertContentEquals(seed, store.items["ssh-identity-$id"], "the account name drifted")
        assertContentEquals(seed, secrets.identitySeed())
    }

    @Test
    fun `an unknown deployment has no identity`() {
        assertNull(secrets.identitySeed())
    }

    /** The accounts are per MACHINE */
    @Test
    fun `two machines keep two passwords`() {
        secrets.setPassword("relay-secret", SSHHostID.VPS)
        secrets.setPassword("home-secret", SSHHostID.HOME)

        assertEquals("relay-secret", secrets.password(SSHHostID.VPS))
        assertEquals("home-secret", secrets.password(SSHHostID.HOME))
    }

    /** Read-forward, to the entry machine only */
    @Test
    fun `a password written before the split answers for the entry machine only`() {
        store.setString("ssh-password-$id", "written-before-the-split")

        assertEquals("written-before-the-split", secrets.password(SSHHostID.VPS))
        assertEquals(null, secrets.password(SSHHostID.HOME))
    }

    @Test
    fun `the inherited password is copied to the machines own account`() {
        store.setString("ssh-password-$id", "inherited")
        secrets.password(SSHHostID.VPS)

        assertEquals(
            "inherited",
            store.string("ssh-password-$id-vps"),
            "the inherited password was never written forward"
        )
    }

    @Test
    fun `a machine with its own password ignores the older item`() {
        store.setString("ssh-password-$id", "the-old-one")
        secrets.setPassword("its-own", SSHHostID.HOME)

        assertEquals("its-own", secrets.password(SSHHostID.HOME))
        assertEquals("the-old-one", secrets.password(SSHHostID.VPS), "and the other machine still inherits")
    }

    @Test
    fun `a pin is stored where the ported names say`() {
        secrets.setHostKeyPin("ssh-ed25519 AAAA", DeploymentNode.LegacySlot.VPS)

        val account = HostKeyPinAccounts.current(id, DeploymentNode.LegacySlot.VPS)
        assertEquals("ssh-ed25519 AAAA", store.string(account))
        assertEquals("ssh-ed25519 AAAA", secrets.hostKeyPin(DeploymentNode.LegacySlot.VPS))
    }

    @Test
    fun `a pre-node pin is copied forward`() {
        val legacy = HostKeyPinAccounts.legacy(id, DeploymentNode.LegacySlot.HOME)
        store.setString(legacy, "ssh-ed25519 OLD")

        assertEquals("ssh-ed25519 OLD", secrets.hostKeyPin(DeploymentNode.LegacySlot.HOME))
        assertEquals(
            "ssh-ed25519 OLD",
            store.string(HostKeyPinAccounts.current(id, DeploymentNode.LegacySlot.HOME))
        )
        assertTrue(
            store.items.containsKey(legacy),
            "the older item was deleted; a build rolled back would ask to trust the host again"
        )
    }

    // ------------------------------------------------- Forgetting a whole server

    @Test
    fun `forgetting a deployment deletes every account it wrote`() {
        secrets.setIdentitySeed(ByteArray(32))
        secrets.setPassword("relay-secret", SSHHostID.VPS)
        secrets.setPassword("home-secret", SSHHostID.HOME)
        secrets.setHostKeyPin("relay-key", DeploymentNode.LegacySlot.VPS)
        secrets.setHostKeyPin("home-key", DeploymentNode.LegacySlot.HOME)
        store.setString(HostKeyPinAccounts.legacy(id, DeploymentNode.LegacySlot.VPS), "old-relay")
        store.setString("ssh-password-$id", "the deployment-wide one")

        secrets.forget(pair)

        assertTrue(store.items.isEmpty(), "left behind: ${store.items.keys}")
    }

    @Test
    fun `a node without a slot has its password and pin deleted too`() {
        val node = DeploymentNode(
            id = "NODE-3",
            endpoint = HostEndpoint(host = "203.0.113.9", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        secrets.setPassword("third-secret", node.sshHost)
        store.setString(HostKeyPinAccounts.current(id, node.id), "third-key")

        secrets.forget(listOf(node))

        assertTrue(store.items.isEmpty(), "left behind: ${store.items.keys}")
    }

    /** The negative half, and the expensive one */
    @Test
    fun `forgetting one deployment leaves another deployment alone`() {
        val other = "9F1C4C2E-0000-0000-0000-000000000002"
        val otherSecrets = DeploymentSecrets(store, other)
        otherSecrets.setIdentitySeed(ByteArray(32) { 7 })
        otherSecrets.setPassword("other-secret", SSHHostID.VPS)
        otherSecrets.setHostKeyPin("other-key", DeploymentNode.LegacySlot.VPS)
        secrets.setIdentitySeed(ByteArray(32))

        secrets.forget(pair)

        assertContentEquals(ByteArray(32) { 7 }, otherSecrets.identitySeed())
        assertEquals("other-secret", otherSecrets.password(SSHHostID.VPS))
        assertEquals("other-key", otherSecrets.hostKeyPin(DeploymentNode.LegacySlot.VPS))
    }

    private val pair = listOf(
        DeploymentNode(
            id = DeploymentNode.nodeID(id, DeploymentNode.LegacySlot.VPS),
            endpoint = HostEndpoint(host = "203.0.113.1", user = "root"),
            capabilities = setOf(NodeCapability.INGRESS),
            legacySlot = DeploymentNode.LegacySlot.VPS,
        ),
        DeploymentNode(
            id = DeploymentNode.nodeID(id, DeploymentNode.LegacySlot.HOME),
            endpoint = HostEndpoint(host = "10.8.0.2", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            legacySlot = DeploymentNode.LegacySlot.HOME,
        ),
    )
}

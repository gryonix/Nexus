package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostKeyPinAccounts
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

class DeploymentSecrets(private val store: SecretStore, private val deploymentID: String) {
    fun identitySeed(): ByteArray? = store.secret("ssh-identity-$deploymentID")

    fun setIdentitySeed(seed: ByteArray) = store.setSecret("ssh-identity-$deploymentID", seed)

    fun forgetIdentitySeed() = store.deleteSecret("ssh-identity-$deploymentID")

    fun pendingTransferID(): String? = store.string("ssh-transfer-$deploymentID")

    fun setPendingTransfer(id: String) = store.setString("ssh-transfer-$deploymentID", id)

    fun clearPendingTransfer() = store.deleteSecret("ssh-transfer-$deploymentID")

    /** The password of an existing account on one MACHINE */
    fun password(host: SSHHostID): String? {
        store.string(passwordAccount(host))?.let { return it }
        if (host != SSHHostID.VPS) return null
        val inherited = store.string(legacyPasswordAccount) ?: return null
        store.setString(passwordAccount(host), inherited)
        return inherited
    }

    fun setPassword(password: String, host: SSHHostID) {
        store.setString(passwordAccount(host), password)
    }

    fun hostKeyPin(nodeID: String): String? = store.string(HostKeyPinAccounts.current(deploymentID, nodeID))

    fun hostKeyPin(slot: DeploymentNode.LegacySlot): String? {
        store.string(HostKeyPinAccounts.current(deploymentID, slot))?.let { return it }
        val legacy = store.string(HostKeyPinAccounts.legacy(deploymentID, slot)) ?: return null
        store.setString(HostKeyPinAccounts.current(deploymentID, slot), legacy)
        return legacy
    }

    fun setHostKeyPin(pin: String, nodeID: String) {
        store.setString(HostKeyPinAccounts.current(deploymentID, nodeID), pin)
    }

    fun setHostKeyPin(pin: String, slot: DeploymentNode.LegacySlot) {
        store.setString(HostKeyPinAccounts.current(deploymentID, slot), pin)
    }

    fun bastionHostKeyPin(endpoint: String): String? =
        store.string(HostKeyPinAccounts.bastion(deploymentID, endpoint))

    fun setBastionHostKeyPin(pin: String, endpoint: String) {
        store.setString(HostKeyPinAccounts.bastion(deploymentID, endpoint), pin)
    }

    fun forgetHostKeyPin(node: DeploymentNode) {
        store.deleteSecret(HostKeyPinAccounts.current(deploymentID, node.id))
        val slot = node.legacySlot ?: return
        store.deleteSecret(HostKeyPinAccounts.current(deploymentID, slot))
        store.deleteSecret(HostKeyPinAccounts.legacy(deploymentID, slot))
    }

    /** Everything this deployment kept behind the keystore, gone */
    fun forget(nodes: List<DeploymentNode>) {
        store.deleteSecret("ssh-identity-$deploymentID")
        store.deleteSecret("ssh-transfer-$deploymentID")
        store.deleteSecret(legacyPasswordAccount)
        for (node in nodes) {
            store.deleteSecret(passwordAccount(node.sshHost))
            store.deleteSecret(HostKeyPinAccounts.current(deploymentID, node.id))
            val slot = node.legacySlot ?: continue
            store.deleteSecret(HostKeyPinAccounts.current(deploymentID, slot))
            store.deleteSecret(HostKeyPinAccounts.legacy(deploymentID, slot))
        }
        for (slot in DeploymentNode.LegacySlot.entries) {
            store.deleteSecret(passwordAccount(SSHHostID(SSHHostID.Kind.Slot(slot))))
            store.deleteSecret(HostKeyPinAccounts.current(deploymentID, slot))
            store.deleteSecret(HostKeyPinAccounts.legacy(deploymentID, slot))
        }
    }

    private val legacyPasswordAccount get() = "ssh-password-$deploymentID"

    private fun passwordAccount(host: SSHHostID): String = when (val kind = host.kind) {
        is SSHHostID.Kind.Slot -> "ssh-password-$deploymentID-${kind.slot.name.lowercase()}"
        is SSHHostID.Kind.Node -> "ssh-password-$deploymentID-node-${kind.id}"
    }
}

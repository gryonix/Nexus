package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostKeyPinAccounts
import com.skaymer.gryonixnexus.servercontrol.KnownHostKey
import com.skaymer.gryonixnexus.servercontrol.KnownHosts

/** The pinned SSH host keys, listed and forgotten */
class KnownHostsStore(private val store: SecretStore) {
    fun rows(deployments: List<Deployment>): List<KnownHostKey> = deployments.flatMap { deployment ->
        val secrets = DeploymentSecrets(store, deployment.id)
        val nodes = KnownHosts.entries(deployment) { node ->
            node.legacySlot?.let { secrets.hostKeyPin(it) } ?: secrets.hostKeyPin(node.id)
        }
        val prefix = HostKeyPinAccounts.bastion(deployment.id, "")
        val endpoints = store.accounts(prefix).map { it.removePrefix(prefix) }.sorted()
        nodes + KnownHosts.bastionEntries(deployment, endpoints) { secrets.bastionHostKeyPin(it) }
    }

    fun forget(row: KnownHostKey, deployments: List<Deployment>) {
        val deployment = deployments.firstOrNull { it.id == row.deploymentID } ?: return
        row.bastionEndpoint?.let {
            store.deleteSecret(HostKeyPinAccounts.bastion(deployment.id, it))
            return
        }
        val node = deployment.nodes.firstOrNull { it.id == row.nodeID } ?: return
        DeploymentSecrets(store, deployment.id).forgetHostKeyPin(node)
    }
}

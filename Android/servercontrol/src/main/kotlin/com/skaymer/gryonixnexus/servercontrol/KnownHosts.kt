package com.skaymer.gryonixnexus.servercontrol

import java.security.MessageDigest
import java.util.Base64

data class KnownHostKey(
    val id: String,
    val serverName: String,
    val machineName: String,
    val endpoint: String,
    val keyType: String,
    val fingerprint: String,
    val bastionEndpoint: String?,
    val deploymentID: String,
    val nodeID: String?,
)

object KnownHosts {
    class Described(val keyType: String, val fingerprint: String)

    /** "ssh-ed25519 AAAA…" as the type and its SHA256 fingerprint */
    fun describe(pin: String): Described? {
        val parts = pin.trim().split(' ').filter { it.isNotEmpty() }
        if (parts.size < 2) return null
        val blob = runCatching { Base64.getDecoder().decode(parts[1]) }.getOrNull()?.takeIf { it.isNotEmpty() }
            ?: return null
        val digest = Base64.getEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(blob))
        return Described(parts[0], "SHA256:$digest")
    }

    fun entries(deployment: Deployment, pin: (DeploymentNode) -> String?): List<KnownHostKey> =
        deployment.nodes.mapNotNull { node ->
            val key = pin(node)?.let(::describe) ?: return@mapNotNull null
            KnownHostKey(
                id = "${deployment.id}/${node.id}",
                serverName = deployment.name,
                machineName = node.name.ifEmpty { node.endpoint.host },
                endpoint = "${node.endpoint.host}:${node.endpoint.port}",
                keyType = key.keyType,
                fingerprint = key.fingerprint,
                bastionEndpoint = null,
                deploymentID = deployment.id,
                nodeID = node.id,
            )
        }

    /** Jump hosts typed in by hand, keyed by their host:port */
    fun bastionEntries(deployment: Deployment, endpoints: List<String>, pin: (String) -> String?): List<KnownHostKey> =
        endpoints.mapNotNull { endpoint ->
            val key = pin(endpoint)?.let(::describe) ?: return@mapNotNull null
            KnownHostKey(
                id = "${deployment.id}/bastion/$endpoint",
                serverName = deployment.name,
                machineName = endpoint,
                endpoint = endpoint,
                keyType = key.keyType,
                fingerprint = key.fingerprint,
                bastionEndpoint = endpoint,
                deploymentID = deployment.id,
                nodeID = null,
            )
        }
}

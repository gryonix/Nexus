package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import java.time.Instant

/** One device in the mesh, in the app's own vocabulary */
data class MeshNode(
    val id: String,
    val name: String,
    /** The addresses it answers on inside the mesh */
    val addresses: List<String>,
    /** Which mesh user it belongs to */
    val user: String,
    val isOnline: Boolean,
    val lastSeen: Instant?,
)

/** A mesh user — what join keys belong to */
data class MeshUser(val id: String, val name: String)

/** One published name and the mesh address it resolves to */
data class MeshName(val name: String, val address: String)

/** A freshly minted join key */
data class MeshAuthKey(
    val key: String,
    val isReusable: Boolean,
    /** null when the server did not say */
    val expiresAt: Instant?,
)

class AgentMeshOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun users(): List<MeshUser> = user { client.listMeshUsers() }

    suspend fun createUser(named: String): List<MeshUser> = user { client.createMeshUser(named) }

    suspend fun mintAuthKey(userID: String, reusable: Boolean, expirationHours: Int): MeshAuthKey {
        val response = gate.gated { client.createMeshAuthKey(userID, reusable, expirationHours) }
        return MeshAuthKey(
            key = response.key,
            isReusable = response.reusable,
            expiresAt = response.expires_at.takeIf { it != 0L }?.let(Instant::ofEpochSecond),
        )
    }

    suspend fun nodes(): List<MeshNode> = node { client.listMeshNodes() }

    suspend fun removeNode(id: String): List<MeshNode> = node { client.deleteMeshNode(id) }

    suspend fun publishNames(names: List<String>, nodeName: String = ""): List<MeshName> =
        gate.gated { client.publishMeshNames(names, nodeName) }
            .map { MeshName(it.name, it.address) }

    // --------------------------------------------------------------- Helpers

    private suspend fun user(call: suspend () -> List<gryonixnexusd.v1.MeshUser>): List<MeshUser> =
        gate.gated(call).map { MeshUser(it.id, it.name) }

    private suspend fun node(call: suspend () -> List<gryonixnexusd.v1.MeshNode>): List<MeshNode> =
        gate.gated(call).map {
            MeshNode(
                id = it.id,
                name = it.name,
                addresses = it.addresses,
                user = it.user,
                isOnline = it.online,
                lastSeen = it.last_seen.takeIf { seconds -> seconds != 0L }?.let(Instant::ofEpochSecond),
            )
        }
}

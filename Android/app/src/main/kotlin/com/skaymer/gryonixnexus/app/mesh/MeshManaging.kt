package com.skaymer.gryonixnexus.app.mesh

import com.skaymer.gryonixnexus.agentcontrol.AgentMeshOperations
import com.skaymer.gryonixnexus.agentcontrol.MeshAuthKey
import com.skaymer.gryonixnexus.agentcontrol.MeshName
import com.skaymer.gryonixnexus.agentcontrol.MeshNode
import com.skaymer.gryonixnexus.agentcontrol.MeshUser

/** What the mesh screen asks of a server */
interface MeshManaging {
    suspend fun nodes(): List<MeshNode>
    suspend fun removeNode(id: String): List<MeshNode>
    suspend fun users(): List<MeshUser>
    suspend fun createUser(named: String): List<MeshUser>
    suspend fun mintAuthKey(userID: String, reusable: Boolean, expirationHours: Int): MeshAuthKey
    suspend fun publishNames(names: List<String>): List<MeshName>
}

class AgentMesh(private val operations: AgentMeshOperations) : MeshManaging {
    override suspend fun nodes() = operations.nodes()
    override suspend fun removeNode(id: String) = operations.removeNode(id)
    override suspend fun users() = operations.users()
    override suspend fun createUser(named: String) = operations.createUser(named)
    override suspend fun mintAuthKey(userID: String, reusable: Boolean, expirationHours: Int) =
        operations.mintAuthKey(userID, reusable, expirationHours)
    override suspend fun publishNames(names: List<String>) = operations.publishNames(names)
}

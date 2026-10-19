package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import gryonixnexusd.v1.PreRestoreCopyList

/** A data folder a restore set aside */
data class PreRestoreCopy(
    val serviceID: String,
    val path: String,
    val sizeBytes: Long,
    /** False when the agent ran out of time measuring it */
    val sizeKnown: Boolean,
    val movedAsideSeconds: Long,
) {
    /** The folder's own name */
    val name: String get() = path.trimEnd('/').substringAfterLast('/')
}

/** Listing and deleting the old copies of one service */
interface PreRestoreManaging {
    suspend fun copies(service: ManagedService): List<PreRestoreCopy>
    suspend fun delete(copy: PreRestoreCopy): List<PreRestoreCopy>
}

class AgentPreRestoreOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : PreRestoreManaging {
    /** The old copies of one service, newest first */
    override suspend fun copies(service: ManagedService): List<PreRestoreCopy> {
        val id = AgentServiceMapping.agentID(service.id)
            ?: throw AgentControlError.UnsupportedService(service.displayName)
        return newestFirst(mapping { client.listPreRestoreCopies(id) })
    }

    /** Deletes one copy, returns the remaining ones */
    override suspend fun delete(copy: PreRestoreCopy): List<PreRestoreCopy> =
        newestFirst(mapping { client.deletePreRestoreCopy(copy.path) })

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("restore") { gate.gated(body) }

    companion object {
        internal fun newestFirst(list: PreRestoreCopyList): List<PreRestoreCopy> =
            list.copies.map {
                PreRestoreCopy(
                    serviceID = it.service_id,
                    path = it.path,
                    sizeBytes = it.size_bytes,
                    sizeKnown = it.size_known,
                    movedAsideSeconds = it.moved_aside_unix,
                )
            }.sortedByDescending { it.movedAsideSeconds }
    }
}

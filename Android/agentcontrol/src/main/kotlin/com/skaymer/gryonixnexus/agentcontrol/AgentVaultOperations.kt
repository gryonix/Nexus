package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.VaultEntry
import gryonixnexusd.v1.VaultSnapshot

class AgentVaultOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
    private val deviceUID: String = "",
) {
    /** What the server holds */
    suspend fun entries(): List<VaultEntry> = snapshot().entries.filter { !it.deleted }

    suspend fun snapshot(): VaultSnapshot = mapping { client.vault() }

    suspend fun save(entries: List<VaultEntry>): VaultSnapshot {
        val stamped = entries.map { entry ->
            if (entry.updated_by.isEmpty()) entry.copy(updated_by = deviceUID) else entry
        }
        return mapping { client.putVaultEntries(stamped) }
    }

    suspend fun delete(id: String): VaultSnapshot =
        mapping { client.deleteVaultEntry(id, deviceUID) }

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("vault") { gate.gated(body) }
}

object VaultMerge {
    fun merged(local: List<VaultEntry>, remote: List<VaultEntry>): List<VaultEntry> =
        resolved(local, remote).filter { !it.deleted }

    /** The same answer WITH the tombstones still in it */
    fun resolved(local: List<VaultEntry>, remote: List<VaultEntry>): List<VaultEntry> {
        val byID = LinkedHashMap<String, VaultEntry>()
        for (entry in local + remote) {
            if (entry.id.isEmpty()) continue
            val held = byID[entry.id]
            if (held != null && !isNewer(entry, held)) continue
            byID[entry.id] = entry
        }
        return byID.values.sortedBy { it.id }
    }

    fun toPush(local: List<VaultEntry>, remote: List<VaultEntry>): List<VaultEntry> {
        val remoteByID = HashMap<String, VaultEntry>()
        for (entry in remote) {
            val held = remoteByID[entry.id]
            if (held == null || isNewer(entry, held)) remoteByID[entry.id] = entry
        }
        return local
            .filter { entry ->
                if (entry.id.isEmpty()) return@filter false
                val theirs = remoteByID[entry.id] ?: return@filter true
                isNewer(entry, theirs)
            }
            .sortedBy { it.id }
    }

    private fun isNewer(lhs: VaultEntry, rhs: VaultEntry): Boolean =
        if (lhs.updated_at != rhs.updated_at) lhs.updated_at > rhs.updated_at
        else lhs.updated_by > rhs.updated_by
}

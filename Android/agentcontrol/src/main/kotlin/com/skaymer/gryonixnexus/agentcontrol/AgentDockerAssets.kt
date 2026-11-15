package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.DockerRemovalResult

data class DockerImageSummary(
    val reference: String,
    val name: String,
    val sizeBytes: Long,
    val containers: Int,
    val createdSince: String,
) {
    val isInUse: Boolean get() = containers > 0
}

data class DockerVolumeSummary(
    val name: String,
    val sizeBytes: Long,
    val containers: Int,
    val isManaged: Boolean,
) {
    val isInUse: Boolean get() = containers > 0
    val isRemovable: Boolean get() = !isInUse && !isManaged
}

data class DockerNetworkSummary(
    val name: String,
    val driver: String,
    val subnet: String,
    val containers: Int,
    val isManaged: Boolean,
    val isBuiltin: Boolean,
    val isInternal: Boolean,
) {
    val isInUse: Boolean get() = containers > 0
    val isRemovable: Boolean get() = !isInUse && !isManaged && !isBuiltin
}

data class DockerPruneSummary(
    val imagesRemoved: Int,
    val volumesRemoved: Int,
    val reclaimedBytes: Long,
    val failures: List<String>,
)

class DockerAssetException(message: String) : Exception(message)

object DockerUsage {
    /** Bytes a prune of unused images and volumes would free */
    fun reclaimable(images: List<DockerImageSummary>, volumes: List<DockerVolumeSummary>): Long =
        images.filter { !it.isInUse }.sumOf { it.sizeBytes } + volumes.filter { it.isRemovable }.sumOf { it.sizeBytes }

    fun total(images: List<DockerImageSummary>, volumes: List<DockerVolumeSummary>): Long =
        images.sumOf { it.sizeBytes } + volumes.sumOf { it.sizeBytes }
}

interface DockerAssetManaging {
    suspend fun images(): List<DockerImageSummary>
    suspend fun volumes(): List<DockerVolumeSummary>
    suspend fun removeImage(reference: String)
    suspend fun removeVolume(name: String)
    suspend fun pruneUnused(images: Boolean, volumes: Boolean): DockerPruneSummary
    suspend fun networks(): List<DockerNetworkSummary> = emptyList()
    suspend fun removeNetwork(name: String) {}
}

class AgentDockerAssets(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : DockerAssetManaging {
    override suspend fun images(): List<DockerImageSummary> {
        val wire = gate.gated { client.listImages() }
        if (wire.unavailable_reason.isNotEmpty()) throw DockerAssetException(wire.unavailable_reason)
        return wire.images.map {
            val untagged = it.repository.isEmpty() || it.repository == "<none>"
            DockerImageSummary(
                reference = it.reference,
                name = if (untagged) it.id else "${it.repository}:${it.tag}",
                sizeBytes = it.size_bytes,
                containers = it.containers,
                createdSince = it.created_since,
            )
        }
    }

    override suspend fun volumes(): List<DockerVolumeSummary> {
        val wire = gate.gated { client.listVolumes() }
        if (wire.unavailable_reason.isNotEmpty()) throw DockerAssetException(wire.unavailable_reason)
        return wire.volumes.map {
            DockerVolumeSummary(it.name, it.size_bytes, it.containers, it.managed)
        }
    }

    override suspend fun removeImage(reference: String) = check(gate.gated { client.removeImage(reference) })

    override suspend fun removeVolume(name: String) = check(gate.gated { client.removeVolume(name) })

    override suspend fun pruneUnused(images: Boolean, volumes: Boolean): DockerPruneSummary {
        val wire = gate.gated { client.pruneUnused(images, volumes) }
        return DockerPruneSummary(wire.images_removed, wire.volumes_removed, wire.reclaimed_bytes, wire.failures)
    }

    override suspend fun networks(): List<DockerNetworkSummary> {
        val wire = gate.gated { client.listNetworks() }
        if (wire.unavailable_reason.isNotEmpty()) throw DockerAssetException(wire.unavailable_reason)
        return wire.networks.map {
            DockerNetworkSummary(it.name, it.driver, it.subnet, it.containers, it.managed, it.builtin, it.internal_)
        }
    }

    override suspend fun removeNetwork(name: String) = check(gate.gated { client.removeNetwork(name) })

    private fun check(result: DockerRemovalResult) {
        if (!result.removed) throw DockerAssetException(result.message)
    }
}

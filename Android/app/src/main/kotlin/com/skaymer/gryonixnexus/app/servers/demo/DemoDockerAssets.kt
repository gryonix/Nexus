package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.DockerImage
import gryonixnexusd.v1.DockerRemovalResult
import gryonixnexusd.v1.DockerVolume
import gryonixnexusd.v1.ImageInventory
import gryonixnexusd.v1.PruneUnusedRequest
import gryonixnexusd.v1.PruneUnusedResult
import gryonixnexusd.v1.RemoveImageRequest
import gryonixnexusd.v1.RemoveVolumeRequest
import gryonixnexusd.v1.VolumeInventory

/** Images and volumes on a demo machine */
object DemoDockerAssets {
    private class Img(val id: String, val repo: String, val tag: String, val size: Long, val used: Int) {
        val reference get() = if (repo == "<none>") id else "$repo:$tag"
    }

    private class Vol(val name: String, val size: Long, val used: Int, val managed: Boolean)

    private val images = listOf(
        Img("3f8a1c9d2b11", "vaultwarden/server", "1.32", 214_000_000, 1),
        Img("a41c77e0d9f2", "nextcloud", "29-apache", 1_120_000_000, 1),
        Img("9b02e5a6c831", "postgres", "16", 432_000_000, 1),
        Img("0c6d4f1ae277", "postgres", "14", 408_000_000, 0),
        Img("e5b3190c7a48", "<none>", "<none>", 96_000_000, 0),
    )

    private val volumes = listOf(
        Vol("vaultwarden_data", 48_000_000, 1, true),
        Vol("nextcloud_html", 2_300_000_000, 1, true),
        Vol("old_postgres14_data", 640_000_000, 0, false),
        Vol("scratch_cache", 12_000_000, 0, false),
    )

    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? =
        DemoAgentState.memory(machine) { memory ->
            when (path.substringAfterLast('/')) {
                "ListImages" -> imageInventory(memory).demoPayload()
                "ListVolumes" -> volumeInventory(memory).demoPayload()
                "RemoveImage" -> removeImage(RemoveImageRequest.ADAPTER.decode(request).reference, memory).demoPayload()
                "RemoveVolume" -> removeVolume(RemoveVolumeRequest.ADAPTER.decode(request).name, memory).demoPayload()
                else -> prune(PruneUnusedRequest.ADAPTER.decode(request), memory).demoPayload()
            }
        }

    private fun imageInventory(memory: DemoAgentState.Memory) = ImageInventory(
        images = images.filter { it.reference !in memory.removedImages }.map {
            DockerImage(
                id = it.id, repository = it.repo, tag = it.tag, size_bytes = it.size, containers = it.used,
                in_use = it.used > 0, created_since = "3 weeks ago", reference = it.reference,
            )
        },
    )

    private fun volumeInventory(memory: DemoAgentState.Memory) = VolumeInventory(
        volumes = volumes.filter { it.name !in memory.removedVolumes }.map {
            DockerVolume(
                name = it.name, driver = "local", size_bytes = it.size, containers = it.used,
                in_use = it.used > 0, managed = it.managed,
            )
        },
    )

    private fun removeImage(reference: String, memory: DemoAgentState.Memory): DockerRemovalResult {
        val image = images.firstOrNull { it.reference == reference }
            ?: return DockerRemovalResult(message = "this host reports no such image")
        if (image.used > 0) return DockerRemovalResult(message = "a container still uses this image")
        memory.removedImages += reference
        return DockerRemovalResult(removed = true)
    }

    private fun removeVolume(name: String, memory: DemoAgentState.Memory): DockerRemovalResult {
        val volume = volumes.firstOrNull { it.name == name }
            ?: return DockerRemovalResult(message = "this host reports no such volume")
        if (volume.used > 0) return DockerRemovalResult(message = "a container still uses this volume")
        if (volume.managed) return DockerRemovalResult(message = "this volume belongs to a managed service")
        memory.removedVolumes += name
        return DockerRemovalResult(removed = true)
    }

    private fun prune(asked: PruneUnusedRequest, memory: DemoAgentState.Memory): PruneUnusedResult {
        var imagesRemoved = 0
        var volumesRemoved = 0
        var bytes = 0L
        if (asked.images) {
            for (image in images.filter { it.used == 0 && it.reference !in memory.removedImages }) {
                memory.removedImages += image.reference
                imagesRemoved++
                bytes += image.size
            }
        }
        if (asked.volumes) {
            for (volume in volumes.filter { it.used == 0 && !it.managed && it.name !in memory.removedVolumes }) {
                memory.removedVolumes += volume.name
                volumesRemoved++
                bytes += volume.size
            }
        }
        return PruneUnusedResult(images_removed = imagesRemoved, volumes_removed = volumesRemoved, reclaimed_bytes = bytes)
    }
}

package com.skaymer.gryonixnexus.servercontrol

import java.io.File

/** Persistence of the deployment list */
interface DeploymentStore {
    fun load(): List<Deployment>
    fun save(deployments: List<Deployment>)
}

/** Insert-or-replace by id */
fun DeploymentStore.upsert(deployment: Deployment) {
    val deployments = load().toMutableList()
    val index = deployments.indexOfFirst { it.id == deployment.id }
    if (index >= 0) deployments[index] = deployment else deployments += deployment
    save(deployments)
}

/** Removes the deployment from the list */
fun DeploymentStore.remove(id: String) {
    save(load().filter { it.id != id })
}

class FileDeploymentStore(private val file: File) : DeploymentStore {
    override fun load(): List<Deployment> {
        if (!file.exists()) return emptyList()
        return DeploymentListCodec.decode(file.readText())
    }

    override fun save(deployments: List<Deployment>) {
        file.parentFile?.mkdirs()
        val staging = File(file.parentFile, "${file.name}.new")
        staging.writeText(DeploymentListCodec.encode(deployments))
        if (!staging.renameTo(file)) {
            staging.copyTo(file, overwrite = true)
            staging.delete()
        }
    }
}

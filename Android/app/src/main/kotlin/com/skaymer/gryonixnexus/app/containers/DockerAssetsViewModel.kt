package com.skaymer.gryonixnexus.app.containers

import com.skaymer.gryonixnexus.agentcontrol.DockerAssetManaging
import com.skaymer.gryonixnexus.agentcontrol.DockerImageSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerNetworkSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerPruneSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerUsage
import com.skaymer.gryonixnexus.agentcontrol.DockerVolumeSummary
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DockerAssetsState(
    val images: List<DockerImageSummary> = emptyList(),
    val volumes: List<DockerVolumeSummary> = emptyList(),
    val networks: List<DockerNetworkSummary> = emptyList(),
    val isLoading: Boolean = false,
    val isWorking: Boolean = false,
    val errorMessage: String? = null,
    val lastPrune: DockerPruneSummary? = null,
) {
    val reclaimableBytes: Long get() = DockerUsage.reclaimable(images, volumes)
    val totalBytes: Long get() = DockerUsage.total(images, volumes)
    val hasUnused: Boolean get() = images.any { !it.isInUse } || volumes.any { it.isRemovable }
}

class DockerAssetsViewModel(
    private val scope: CoroutineScope,
    private val assets: suspend (Deployment) -> DockerAssetManaging,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(DockerAssetsState())
    val state: StateFlow<DockerAssetsState> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        scope.launch { read(deployment) }
    }

    fun removeImage(deployment: Deployment, image: DockerImageSummary) =
        change(deployment) { it.removeImage(image.reference) }

    fun removeVolume(deployment: Deployment, volume: DockerVolumeSummary) =
        change(deployment) { it.removeVolume(volume.name) }

    fun removeNetwork(deployment: Deployment, network: DockerNetworkSummary) =
        change(deployment) { it.removeNetwork(network.name) }

    fun pruneUnused(deployment: Deployment) = change(deployment) {
        val summary = it.pruneUnused(images = true, volumes = true)
        _state.value = _state.value.copy(lastPrune = summary)
        if (summary.failures.isNotEmpty()) throw IllegalStateException(summary.failures.joinToString("\n"))
    }

    private fun change(deployment: Deployment, body: suspend (DockerAssetManaging) -> Unit) {
        scope.launch {
            _state.value = _state.value.copy(isWorking = true, lastPrune = null, errorMessage = null)
            val failure = attempt(deployment) { body(assets(deployment)) }
            read(deployment)
            _state.value = _state.value.copy(isWorking = false, errorMessage = failure ?: _state.value.errorMessage)
        }
    }

    private suspend fun read(deployment: Deployment) {
        _state.value = _state.value.copy(isLoading = true)
        val failure = attempt(deployment) {
            val client = assets(deployment)
            val networks = runCatching { client.networks() }.getOrDefault(emptyList())
            _state.value = _state.value.copy(images = client.images(), volumes = client.volumes(), networks = networks)
        }
        _state.value = _state.value.copy(isLoading = false, errorMessage = failure)
    }

    private suspend fun attempt(deployment: Deployment, body: suspend () -> Unit): String? = try {
        body()
        null
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        failure.message ?: failure::class.simpleName.orEmpty()
    }
}

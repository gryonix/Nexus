package com.skaymer.gryonixnexus.app.mesh

import com.skaymer.gryonixnexus.agentcontrol.MeshAuthKey
import com.skaymer.gryonixnexus.agentcontrol.MeshName
import com.skaymer.gryonixnexus.agentcontrol.MeshNode
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.services.HeadscaleService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt

/** What the mesh screen is showing for one server */
data class MeshState(
    val nodes: List<MeshNode> = emptyList(),
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
    val notice: String? = null,
    val hasAnswered: Boolean = false,
    val joinKey: MeshAuthKey? = null,
    val isMinting: Boolean = false,
    val publishedNames: List<MeshName> = emptyList(),
) {
    /** Whether the screen may say "this mesh has no devices" */
    val saysThereAreNone: Boolean
        get() = hasAnswered && nodes.isEmpty() && !isBusy && errorMessage == null
}

class MeshViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> MeshManaging,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(MeshState())
    val state: StateFlow<MeshState> = _state.asStateFlow()

    private var job: Job? = null

    /** Read the device list */
    fun load(deployment: Deployment) {
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(isBusy = true, errorMessage = null, notice = null)
            run(deployment) { it.nodes() }
        }
    }

    /** Take one device out of the mesh */
    fun remove(deployment: Deployment, id: String) {
        scope.launch {
            _state.value = _state.value.copy(isBusy = true, errorMessage = null, notice = null)
            run(deployment, notice = REMOVED) { it.removeNode(id) }
        }
    }

    /** Mint a join key for a new device */
    fun mintJoinKey(deployment: Deployment) {
        if (!LicensePrompt.allow()) return
        scope.launch {
            _state.value = _state.value.copy(isMinting = true, errorMessage = null, notice = null)
            try {
                val mesh = operations(deployment)
                val existing = mesh.users().firstOrNull { it.name == DEVICE_USER }
                val user = existing ?: mesh.createUser(DEVICE_USER)
                    .firstOrNull { it.name == DEVICE_USER }
                if (user == null) {
                    _state.value = _state.value.copy(
                        isMinting = false,
                        errorMessage = "The mesh server did not create the user.",
                    )
                    return@launch
                }
                val key = mesh.mintAuthKey(user.id, reusable = false, expirationHours = 24)
                _state.value = _state.value.copy(isMinting = false, joinKey = key)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(isMinting = false, errorMessage = reason(failure))
            }
        }
    }

    /** Forgets the key the moment the sheet showing it closes */
    fun clearJoinKey() {
        _state.value = _state.value.copy(joinKey = null)
    }

    /** Publish every name this deployment serves into the mesh */
    fun publishNames(deployment: Deployment) {
        scope.launch {
            _state.value = _state.value.copy(isBusy = true, errorMessage = null, notice = null)
            try {
                val records = operations(deployment).publishNames(publishableNames(deployment))
                _state.value = _state.value.copy(
                    isBusy = false,
                    publishedNames = records,
                    notice = if (records.isEmpty()) NAMES_CLEARED else PUBLISHED,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(isBusy = false, errorMessage = reason(failure))
            }
        }
    }

    fun reset() {
        job?.cancel()
        job = null
        _state.value = MeshState()
    }

    private suspend fun run(
        deployment: Deployment,
        notice: String? = null,
        call: suspend (MeshManaging) -> List<MeshNode>,
    ) {
        try {
            val nodes = call(operations(deployment))
            _state.value = _state.value.copy(
                nodes = nodes,
                isBusy = false,
                errorMessage = null,
                notice = notice,
                hasAnswered = true,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            // The devices are KEPT — see the class note.
            _state.value = _state.value.copy(
                isBusy = false,
                errorMessage = reason(failure),
                hasAnswered = true,
            )
        }
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        const val DEVICE_USER = "devices"

        const val REMOVED = "The device was removed."
        const val PUBLISHED = "The names now resolve inside the mesh."
        const val NAMES_CLEARED = "The published names were cleared."

        fun managesMesh(deployment: Deployment, agentTransportAvailable: Boolean): Boolean =
            deployment.usesAgent &&
                agentTransportAvailable &&
                deployment.services.contains(ServiceID.HEADSCALE)

        /** Where a joining device is told to log in */
        fun loginServer(deployment: Deployment): String =
            "https://" + HeadscaleService().hostname(deployment.serviceContext)

        /** The command a device runs to join */
        fun joinCommand(deployment: Deployment, key: MeshAuthKey): String =
            "tailscale up --login-server ${loginServer(deployment)} --authkey ${key.key}"

        /** Every hostname the deployment serves over the web, aliases included */
        fun publishableNames(deployment: Deployment): List<String> {
            val context = deployment.serviceContext
            return deployment.services
                .mapNotNull { ServiceRegistry.service(it) }
                .mapNotNull { it.webIngress(context) }
                .flatMap { context.servedHostnames(it.hostname) }
                .distinct()
        }
    }
}

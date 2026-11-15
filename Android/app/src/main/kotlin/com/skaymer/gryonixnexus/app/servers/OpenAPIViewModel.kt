package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentcontrol.OpenAPIAccess
import com.skaymer.gryonixnexus.agentcontrol.OpenAPISite
import com.skaymer.gryonixnexus.catalog.ServiceAPIGroup
import com.skaymer.gryonixnexus.catalog.ServiceAPIGroups
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the app knows of one server's open APIs */
data class OpenAPIState(
    val sites: Map<String, OpenAPISite>? = null,
    val loading: Boolean = false,
    val busy: Set<ServiceID> = emptySet(),
    val failure: String? = null,
) {
    fun site(id: ServiceID): OpenAPISite? = sites?.get(id.rawValue)

    fun isOpen(group: ServiceAPIGroup, id: ServiceID): Boolean =
        group.id in ServiceAPIGroups.openGroups(id, site(id)?.paths.orEmpty())

    fun canChange(id: ServiceID): Boolean = site(id)?.editable == true && id !in busy

    /** True all open, false all closed, else null */
    fun allOpen(services: List<ServiceID>): Boolean? {
        val states = services.filter { site(it)?.editable == true }.flatMap { id ->
            ServiceAPIGroups.groups(id).map { isOpen(it, id) }
        }
        val first = states.firstOrNull() ?: return null
        return if (states.all { it == first }) first else null
    }
}

/** Which app APIs of a server answer without the VPN */
class OpenAPIViewModel(
    private val scope: CoroutineScope,
    private val access: suspend (Deployment) -> OpenAPIAccess,
) {
    private val _state = MutableStateFlow(OpenAPIState())
    val state: StateFlow<OpenAPIState> = _state.asStateFlow()
    private var shown: String? = null

    fun refresh(deployment: Deployment) {
        if (shown != deployment.id) _state.value = OpenAPIState()
        shown = deployment.id
        scope.launch {
            _state.value = _state.value.copy(loading = true)
            _state.value = try {
                _state.value.copy(sites = access(deployment).sites(), loading = false, failure = null)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                _state.value.copy(loading = false, failure = reason(failure))
            }
        }
    }

    fun set(deployment: Deployment, id: ServiceID, group: ServiceAPIGroup, open: Boolean) {
        val groups = ServiceAPIGroups.openGroups(id, _state.value.site(id)?.paths.orEmpty()).toMutableSet()
        if (open) groups += group.id else groups -= group.id
        scope.launch { apply(deployment, id, groups) }
    }

    /** Opens and closes several groups of one service together */
    fun setGroups(deployment: Deployment, id: ServiceID, changes: Map<String, Boolean>) {
        val groups = ServiceAPIGroups.openGroups(id, _state.value.site(id)?.paths.orEmpty()).toMutableSet()
        changes.forEach { (group, open) -> if (open) groups += group else groups -= group }
        scope.launch { apply(deployment, id, groups) }
    }

    /** Opens or closes every API of these services */
    fun setAll(deployment: Deployment, open: Boolean, services: List<ServiceID>) {
        scope.launch {
            for (id in services.filter { _state.value.site(it)?.editable == true }) {
                apply(deployment, id, if (open) ServiceAPIGroups.groups(id).map { it.id }.toSet() else emptySet())
            }
        }
    }

    private suspend fun apply(deployment: Deployment, id: ServiceID, groups: Set<String>) {
        val paths = ServiceAPIGroups.paths(id, groups, _state.value.site(id)?.paths.orEmpty())
        _state.value = _state.value.copy(busy = _state.value.busy + id)
        _state.value = try {
            _state.value.copy(sites = access(deployment).set(id.rawValue, paths), failure = null, busy = _state.value.busy - id)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            _state.value.copy(failure = reason(failure), busy = _state.value.busy - id)
        }
    }

    private fun reason(failure: Exception): String = failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        /** Installed services that offer an API */
        fun services(deployment: Deployment): List<ServiceID> =
            deployment.services.filter { ServiceAPIGroups.groups(it).isNotEmpty() }.sortedBy { it.rawValue }
    }
}

/** Demo servers' open APIs, kept in memory */
class DemoOpenAPIAccess(private val deployment: Deployment) : OpenAPIAccess {
    private val chosen = mutableMapOf<String, List<String>>()

    override suspend fun sites(): Map<String, OpenAPISite> =
        OpenAPIViewModel.services(deployment).associate { id ->
            id.rawValue to OpenAPISite(id.rawValue, chosen[id.rawValue] ?: defaultPaths(id), editable = true)
        }

    override suspend fun set(serviceID: String, paths: List<String>): Map<String, OpenAPISite> {
        chosen[serviceID] = paths
        return sites()
    }

    private fun defaultPaths(id: ServiceID): List<String> =
        if (id in OPEN_BY_DEFAULT) ServiceAPIGroups.groups(id).flatMap { it.paths } else emptyList()

    private companion object {
        val OPEN_BY_DEFAULT = setOf(ServiceID.VAULTWARDEN, ServiceID.MAILCOW, ServiceID.N8N)
    }
}

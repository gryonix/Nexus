package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ForwardedPorts
import com.skaymer.gryonixnexus.catalog.HomeOnlyPorts
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PublicPortProbe
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Toggles a service's relay exposure */
class HomeOnlyController(
    private val scope: CoroutineScope,
    private val persist: (Deployment) -> Unit,
    private val reprovision: suspend (Deployment) -> Unit,
    private val guardHost: (Deployment, String, Boolean) -> Unit,
    private val probe: suspend (Deployment, List<Int>) -> List<Int>? = { _, _ -> null },
    val dns: HomeOnlyDNS? = null,
    val rootCA: suspend (Deployment) -> String = { "" },
    val localAliases: suspend (Deployment, String?, Boolean) -> Map<String, String> = { _, _, _ -> emptyMap() },
    private val keepPortsHome: suspend (Deployment, List<Pair<String, Int>>) -> Unit = { _, _ -> },
) {
    private val _verdicts = MutableStateFlow<Map<ServiceID, PublicPortProbe.Verdict>>(emptyMap())
    val verdicts: StateFlow<Map<ServiceID, PublicPortProbe.Verdict>> = _verdicts
    private val _applying = MutableStateFlow<Set<ServiceID>>(emptySet())
    val applying: StateFlow<Set<ServiceID>> = _applying
    private val _failures = MutableStateFlow<Map<ServiceID, Failure>>(emptyMap())
    val failures: StateFlow<Map<ServiceID, Failure>> = _failures

    /** Why a switch did not fully apply */
    sealed interface Failure {
        data object AgentTooOld : Failure

        data class Told(val message: String) : Failure
    }

    fun set(deployment: Deployment, service: ManagedService, homeOnly: Boolean) {
        val hadNoVPN = service.id in deployment.homeOnlyNoVPN
        val changed = changedByToggle(deployment, service.id, homeOnly)
        val portsChanged = AddServiceViewModel.forwardedPorts(deployment) != AddServiceViewModel.forwardedPorts(changed)
        persist(changed)
        service.webIngress(changed.serviceContext)?.let {
            if (homeOnly) guardHost(changed, it.hostname, false) else if (hadNoVPN) guardHost(changed, it.hostname, true)
        }
        if (!homeOnly) _verdicts.update { it - service.id }
        _applying.update { it + service.id }
        scope.launch {
            val failure = apply(changed, portsChanged)
            _failures.update { if (failure == null) it - service.id else it + (service.id to failure) }
            _applying.update { it - service.id }
            if (homeOnly) check(changed, service)
        }
    }

    /** Moves the ports; returns what went wrong */
    private suspend fun apply(changed: Deployment, portsChanged: Boolean): Failure? {
        var failure: Failure? = null
        if (portsChanged && changed.hasRelayIngress) {
            runCatching { reprovision(changed) }.onFailure { failure = told(it) }
        }
        val ports = homeOnlyPorts(changed)
        runCatching { keepPortsHome(changed, ports) }.onFailure {
            val outdated = com.skaymer.gryonixnexus.app.agent.AgentOutdated.matches(it)
            if (!outdated) failure = told(it)
            if (outdated && !changed.hasRelayIngress && ports.isNotEmpty()) failure = Failure.AgentTooOld
        }
        return failure
    }

    private fun told(error: Throwable): Failure = Failure.Told(error.message ?: error.javaClass.simpleName)

    fun setNoVPN(deployment: Deployment, service: ManagedService, noVPN: Boolean) {
        val changed = deployment.copy(
            homeOnlyNoVPN = if (noVPN) deployment.homeOnlyNoVPN + service.id else deployment.homeOnlyNoVPN - service.id,
        )
        persist(changed)
        service.webIngress(changed.serviceContext)?.let { guardHost(changed, it.hostname, !noVPN) }
    }

    /** Remembers that a service's public record is gone, or back */
    fun markDNSRemoved(deployment: Deployment, service: ManagedService, removed: Boolean) {
        persist(
            deployment.copy(
                homeOnlyDNSRemoved = if (removed) deployment.homeOnlyDNSRemoved + service.id else deployment.homeOnlyDNSRemoved - service.id,
            ),
        )
    }

    suspend fun check(deployment: Deployment, service: ManagedService) {
        _verdicts.update { it - service.id }
        val ports = PublicPortProbe.ports(service, deployment)
        if (ports.isEmpty() || !deployment.hasRelayIngress) return
        val open = runCatching { probe(deployment, ports) }.getOrNull() ?: return
        _verdicts.update { it + (service.id to PublicPortProbe.verdict(ports, open)) }
    }

    companion object {
        /** Every home-only port, as the agent takes them */
        fun homeOnlyPorts(deployment: Deployment): List<Pair<String, Int>> =
            HomeOnlyPorts.of(ServiceRegistry.services(deployment.homeOnlyServices), deployment.serviceContext)
                .map { it.proto.wireValue to it.port }

        fun changedByToggle(deployment: Deployment, id: ServiceID, homeOnly: Boolean): Deployment = with(deployment) {
            copy(
                homeOnlyServices = if (homeOnly) homeOnlyServices + id else homeOnlyServices - id,
                homeOnlyNoVPN = if (homeOnly) homeOnlyNoVPN else homeOnlyNoVPN - id,
            )
        }

        fun offers(deployment: Deployment, service: ManagedService): Boolean {
            val context = deployment.serviceContext
            service.webIngress(context)?.let { return !it.homeOnly }
            if (!deployment.closesServicesAtHome) return false
            return ForwardedPorts.tcp(listOf(service), context).any { it != 80 } ||
                ForwardedPorts.udp(listOf(service), context).isNotEmpty()
        }

        fun isHomeOnly(deployment: Deployment, id: ServiceID): Boolean = id in deployment.homeOnlyServices
    }
}

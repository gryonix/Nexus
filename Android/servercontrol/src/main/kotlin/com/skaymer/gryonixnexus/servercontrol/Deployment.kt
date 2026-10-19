package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** How a metrics card draws its CPU/Mem/Disk load */
@Serializable
enum class MetricsIndicatorStyle {
    @SerialName("bars") BARS,

    /** One continuous rounded track per metric */
    @SerialName("track") TRACK,

    @SerialName("rings") RINGS,

    /** Metric name + big value with a thin full-width underline */
    @SerialName("minimal") MINIMAL,
}

/** How big this server's card is drawn */
@Serializable
enum class ServerCardSize {
    @SerialName("wide") WIDE,
    @SerialName("compact") COMPACT,
}

@Serializable
enum class NodeCapability {
    @SerialName("ingress") INGRESS,
    @SerialName("worker") WORKER,
}

/** SSH entry point of one machine */
@Serializable
data class HostEndpoint(
    val host: String,
    val port: Int = 22,
    val user: String,
) {
    val isValid: Boolean
        get() = host.isNotEmpty() && user.isNotEmpty() && port in 1..65535
}

@Serializable
data class OperationTimeouts(
    val quickSeconds: Int = 15,
    val restartSeconds: Int = 60,
    /** Docker service restarts (mailcow compose restart) take longer */
    val serviceRestartSeconds: Int = 120,
    /** Updates and backups — up to ten minutes */
    val longSeconds: Int = 600,
) {
    fun duration(timeoutClass: ServiceCommand.TimeoutClass): Duration = when (timeoutClass) {
        ServiceCommand.TimeoutClass.QUICK -> quickSeconds.seconds
        ServiceCommand.TimeoutClass.RESTART -> serviceRestartSeconds.seconds
        ServiceCommand.TimeoutClass.LONG -> longSeconds.seconds
    }
}

/** One machine of a deployment */
@Serializable
data class DeploymentNode(
    val id: String,
    /** Empty for the migrated pair, which never had one */
    val name: String = "",
    val endpoint: HostEndpoint,
    val capabilities: Set<NodeCapability>,
    /** Which ingress publishes this worker's services */
    val routedThrough: String? = null,
    val servesOwnTraffic: Boolean = false,
    /** The two-slot identity secrets are still keyed by */
    val legacySlot: LegacySlot? = null,
    /** The distribution answer for THIS host; per-host since the beginning */
    val distribution: String? = null,
) {
    @Serializable
    enum class LegacySlot {
        @SerialName("vps") VPS,
        @SerialName("home") HOME,
    }

    companion object {
        fun nodeID(deployment: String, slot: LegacySlot): String {
            val mask = if (slot == LegacySlot.VPS) 0x01L else 0x02L
            val uuid = runCatching { java.util.UUID.fromString(deployment) }.getOrNull()
                ?: return "$deployment-${slot.name.lowercase()}"
            return java.util.UUID(
                uuid.mostSignificantBits,
                uuid.leastSignificantBits xor mask,
            ).toString().uppercase()
        }
    }

    val runsServices: Boolean get() = capabilities.contains(NodeCapability.WORKER)
    val isIngress: Boolean get() = capabilities.contains(NodeCapability.INGRESS)
    val terminatesPublicTraffic: Boolean get() = capabilities.contains(NodeCapability.INGRESS)

    /** How the transport addresses this machine */
    val sshHost: SSHHostID
        get() = legacySlot?.let { SSHHostID(SSHHostID.Kind.Slot(it)) } ?: SSHHostID.node(id)
}

@Serializable
data class ServicePlacement(
    val byService: Map<String, String> = emptyMap(),
) {
    val isEmpty: Boolean get() = byService.isEmpty()

    operator fun get(service: ServiceID): String? = byService[service.rawValue]
}

@Serializable
data class Deployment(
    val id: String,
    /** User-facing label, e.g */
    val name: String,
    val topology: Topology,
    val domain: String = "",
    val additionalDomains: List<String> = emptyList(),
    /** SSH entry point: scenario A — the server; B — the VPS */
    val entry: HostEndpoint,
    val homeWGAddress: String? = null,
    val wgInterface: String = "wg0",
    val services: Set<ServiceID> = emptySet(),
    val serviceSettings: ServiceSettings = ServiceSettings(),
    val timeouts: OperationTimeouts = OperationTimeouts(),
    /** Free-form labels ("web", "prod") — the filter chips in the list */
    val tags: List<String> = emptyList(),
    /** Per-server indicator style; absent follows the app-level setting */
    val metricsIndicatorStyle: MetricsIndicatorStyle? = null,
    val usesPasswordAuth: Boolean = false,
    val usesAgent: Boolean = false,
    val iconSymbol: String? = null,
    val tintName: String? = null,
    val cardSize: ServerCardSize? = null,
    val scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
    /** Machines beyond what [entry]/[homeWGAddress] can describe */
    val storedNodes: List<DeploymentNode>? = null,
    val placement: ServicePlacement? = null,
    val wakeOnLANMAC: String? = null,
    /** The broadcast address read from the machine */
    val wakeOnLANBroadcast: String? = null,
    /** Runs the VPN on the relay instead of at home */
    val vpnOnRelay: Boolean? = null,
) {
    val serviceContext: ServiceContext
        get() = ServiceContext(
            domain = domain,
            additionalDomains = additionalDomains,
            sshUser = entry.user,
            settings = serviceSettings,
            installedServices = services,
            usesInternalTLS = scope.usesInternalTLS,
        )

    val dashboardConfig: DashboardConfig
        get() = DashboardConfig(
            vpsHost = entry.host,
            sshPort = entry.port,
            sshUser = entry.user,
            homeWGAddress = homeWGAddress.orEmpty(),
            wgInterface = wgInterface,
            mailcowPath = serviceSettings.mailcowPath,
            vaultwardenContainer = serviceSettings.vaultwardenContainer,
            vaultwardenDataPath = serviceSettings.vaultwardenDataPath,
            mailcowBackupDir = serviceSettings.mailcowBackupDir,
            vaultwardenBackupDir = serviceSettings.vaultwardenBackupDir,
            backupRetention = serviceSettings.backupRetention,
            quickTimeoutSeconds = timeouts.quickSeconds,
            restartTimeoutSeconds = timeouts.restartSeconds,
            mailcowRestartTimeoutSeconds = timeouts.serviceRestartSeconds,
            longTimeoutSeconds = timeouts.longSeconds,
        )

    val isMultiHost: Boolean get() = nodes.size > 1

    val hasRelayIngress: Boolean
        get() = nodes.any { it.terminatesPublicTraffic && !it.runsServices }

    /** A machine that can take a USB drive */
    val hasPhysicalAccess: Boolean
        get() = topology == Topology.VPS_RELAY_WITH_HOME_BACKEND ||
            scope == DeploymentScope.LOCAL_ONLY || scope == DeploymentScope.DYNAMIC_DNS

    val hasHomeHost: Boolean
        get() = nodes.any { it.routedThrough != null && it.endpoint.host.isNotEmpty() }

    val nodes: List<DeploymentNode>
        get() = storedNodes?.takeIf { it.isNotEmpty() } ?: derivedNodes

    /** The two-host shape, as nodes */
    val derivedNodes: List<DeploymentNode>
        get() {
            if (topology != Topology.VPS_RELAY_WITH_HOME_BACKEND) {
                return listOf(
                    DeploymentNode(
                        id = DeploymentNode.nodeID(id, DeploymentNode.LegacySlot.VPS),
                        endpoint = entry,
                        capabilities = setOf(NodeCapability.INGRESS, NodeCapability.WORKER),
                        legacySlot = DeploymentNode.LegacySlot.VPS,
                    ),
                )
            }
            val relayID = DeploymentNode.nodeID(id, DeploymentNode.LegacySlot.VPS)
            return listOf(
                DeploymentNode(
                    id = relayID,
                    endpoint = entry,
                    capabilities = setOf(NodeCapability.INGRESS),
                    legacySlot = DeploymentNode.LegacySlot.VPS,
                ),
                DeploymentNode(
                    id = DeploymentNode.nodeID(id, DeploymentNode.LegacySlot.HOME),
                    endpoint = HostEndpoint(
                        host = homeWGAddress.orEmpty(),
                        port = entry.port,
                        user = entry.user,
                    ),
                    capabilities = setOf(NodeCapability.WORKER),
                    routedThrough = relayID,
                    servesOwnTraffic = true,
                    legacySlot = DeploymentNode.LegacySlot.HOME,
                ),
            )
        }

    /** The node that runs services — where an install goes */
    val servicesNode: DeploymentNode? get() = nodes.firstOrNull { it.runsServices }

    /** The node that answers on the public address */
    val ingressNode: DeploymentNode? get() = nodes.firstOrNull { it.terminatesPublicTraffic }

    val teardownOrder: List<DeploymentNode>
        get() {
            val remaining = nodes.toMutableList()
            val ordered = mutableListOf<DeploymentNode>()
            while (remaining.isNotEmpty()) {
                val free = remaining.filter { candidate ->
                    remaining.none { it.routedThrough == candidate.id }
                }
                if (free.isEmpty()) {
                    ordered += remaining
                    break
                }
                ordered += free
                val done = free.map { it.id }.toSet()
                remaining.removeAll { it.id in done }
            }
            return ordered
        }

    /** The node that runs [service] */
    fun nodeRunning(service: ServiceID): DeploymentNode? {
        if (vpnRunsOnRelay && service in ServiceID.VPN_FAMILY) return relayNode
        val workers = nodes.filter { it.runsServices }
        val named = placement?.get(service)
        return workers.firstOrNull { named != null && it.id.equals(named, ignoreCase = true) }
            ?: workers.firstOrNull()
    }

    val servicesHost: SSHHostID
        get() = (servicesNode ?: nodes.firstOrNull())?.sshHost ?: SSHHostID.VPS

    /** Every machine of this deployment that runs an agent */
    val agentHosts: List<SSHHostID>
        get() = if (hasRelayIngress && servicesHost != SSHHostID.VPS) listOf(servicesHost, SSHHostID.VPS)
        else listOf(servicesHost)

    fun hostRunning(service: ServiceID): SSHHostID =
        nodeRunning(service)?.sshHost ?: servicesHost

    val workerHosts: List<SSHHostID>
        get() {
            val workers = nodes.filter { it.runsServices }.map { it.sshHost }
            return workers.ifEmpty { listOf(servicesHost) }
        }

    fun servicesByNode(): Map<String, Set<ServiceID>> {
        val grouped = mutableMapOf<String, MutableSet<ServiceID>>()
        for (service in services) {
            val node = nodeRunning(service) ?: continue
            grouped.getOrPut(node.id) { mutableSetOf() }.add(service)
        }
        return grouped
    }
}

object DeploymentListCodec {
    val json: Json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
        prettyPrint = true
    }

    fun decode(text: String): List<Deployment> = json.decodeFromString(text)

    fun encode(deployments: List<Deployment>): String = json.encodeToString(deployments)
}

package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.ServiceAction
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Which saved server and machine each relay id belongs to */
object RelayServers {
    private const val PREFIX = "push.relayServer."

    fun remember(store: SettingsStore, serverId: String, deploymentId: String, host: SSHHostID) {
        if (serverId.isEmpty()) return
        val value = "$deploymentId|${hostKey(host)}"
        if (store.string(PREFIX + serverId) != value) store.setString(PREFIX + serverId, value)
    }

    fun target(store: SettingsStore, serverId: String): Pair<String, SSHHostID?>? {
        val parts = store.string(PREFIX + serverId)?.split("|", limit = 2) ?: return null
        return parts[0] to parts.getOrNull(1)?.let(::host)
    }

    fun hostKey(host: SSHHostID): String = when (val kind = host.kind) {
        is SSHHostID.Kind.Slot -> kind.slot.name.lowercase()
        is SSHHostID.Kind.Node -> "node:${kind.id}"
    }

    fun host(key: String): SSHHostID? = when {
        key.startsWith("node:") -> SSHHostID.node(key.removePrefix("node:"))
        else -> DeploymentNode.LegacySlot.entries.firstOrNull { it.name.lowercase() == key }
            ?.let { SSHHostID(SSHHostID.Kind.Slot(it)) }
    }
}

/** A button tapped on a server alert */
data class AlertAction(val verb: Verb, val server: String, val host: String, val target: String) {
    enum class Verb(val id: String) {
        BLOCK("gnx.action.block"),
        RESTART("gnx.action.restart"),
    }

    companion object {
        /** The buttons an alert of this kind offers */
        fun verbs(kind: String): List<Verb> = when (kind) {
            "gnx.alert.ssh_login" -> listOf(Verb.BLOCK)
            "gnx.alert.service" -> listOf(Verb.RESTART)
            else -> emptyList()
        }

        /** The relay's alert data; null when not JSON */
        fun data(gnx: String?): JsonObject? =
            gnx?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }

        fun from(verb: Verb, gnx: JsonObject): AlertAction? {
            val server = gnx["server_id"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() } ?: return null
            val args = runCatching { gnx["args"]?.jsonArray?.map { it.jsonPrimitive.content } }.getOrNull().orEmpty()
            val target = when (verb) {
                Verb.BLOCK -> gnx["address"]?.jsonPrimitive?.contentOrNull
                Verb.RESTART -> args.getOrNull(1)
            }?.takeIf { it.isNotEmpty() } ?: return null
            return AlertAction(verb, server, args.firstOrNull().orEmpty(), target)
        }
    }
}

/** How a tapped alert button ended */
sealed class AlertOutcome {
    data class Blocked(val address: String) : AlertOutcome()
    data class Restarted(val name: String) : AlertOutcome()
    data class Gone(val name: String) : AlertOutcome()
    object UnknownServer : AlertOutcome()
    data class Failed(val reason: String) : AlertOutcome()
}

/** Does an alert button's job on the sending machine */
class AlertActionRunner(
    private val store: SettingsStore,
    private val deployments: () -> List<Deployment>,
    private val client: suspend (Deployment, SSHHostID) -> AgentClient,
) {
    suspend fun run(action: AlertAction): AlertOutcome = try {
        val (deploymentId, host) = RelayServers.target(store, action.server) ?: return AlertOutcome.UnknownServer
        val deployment = deployments().firstOrNull { it.id == deploymentId } ?: return AlertOutcome.UnknownServer
        val agent = client(deployment, host ?: deployment.servicesHost)
        when (action.verb) {
            AlertAction.Verb.BLOCK -> block(agent, action.target)
            AlertAction.Verb.RESTART -> restart(agent, action.target)
        }
    } catch (failure: kotlinx.coroutines.CancellationException) {
        throw failure
    } catch (failure: Exception) {
        AlertOutcome.Failed(failure.message ?: failure.toString())
    }

    private suspend fun block(agent: AgentClient, address: String): AlertOutcome {
        agent.setSecurityDecision(address, banned = true, durationSeconds = BAN_SECONDS)
        return AlertOutcome.Blocked(address)
    }

    private suspend fun restart(agent: AgentClient, container: String): AlertOutcome {
        val group = agent.listContainers().groups.firstOrNull { group -> group.containers.any { it.name == container } }
            ?: return AlertOutcome.Gone(container)
        agent.controlContainerGroup(group.key, ServiceAction.SERVICE_ACTION_RESTART).collect {}
        return AlertOutcome.Restarted(group.display_name.ifEmpty { container })
    }

    companion object {
        const val BAN_SECONDS = 24L * 3600
    }
}

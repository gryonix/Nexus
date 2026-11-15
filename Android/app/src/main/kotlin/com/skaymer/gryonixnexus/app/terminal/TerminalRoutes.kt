package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HomePathChoice
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import com.skaymer.gryonixnexus.transport.TerminalLogin

/** The routes a terminal tries, in order */
object TerminalRoutes {
    /** Short, so a missing network costs seconds */
    const val LOCAL_TIMEOUT_MS = 4_000

    /** The entry machine, then its fallback address */
    fun entry(primary: TerminalEndpoint, fallback: TerminalEndpoint?): List<TerminalEndpoint> =
        listOfNotNull(
            primary.copy(kind = TerminalEndpoint.Kind.DIRECT),
            fallback?.copy(kind = TerminalEndpoint.Kind.FALLBACK_ADDRESS),
        )

    /** Through the relay, then straight to the tunnel address */
    fun relayed(relayed: TerminalEndpoint): List<TerminalEndpoint> = listOf(
        relayed.copy(kind = TerminalEndpoint.Kind.RELAY),
        relayed.copy(
            parent = null,
            kind = TerminalEndpoint.Kind.TUNNEL_ADDRESS,
            connectTimeoutMs = LOCAL_TIMEOUT_MS,
        ),
    )

    /** Routes the chosen path allows */
    fun allowed(routes: List<TerminalEndpoint>, choice: HomePathChoice): List<TerminalEndpoint> = when (choice) {
        HomePathChoice.AUTOMATIC -> routes
        HomePathChoice.THROUGH_VPS -> routes.filter { it.kind != TerminalEndpoint.Kind.LOCAL_NETWORK }
        HomePathChoice.LOCAL_NETWORK -> routes.filter { it.kind == TerminalEndpoint.Kind.LOCAL_NETWORK }
    }

    /** The local network address first, then the relayed routes */
    fun behindVPS(relayed: TerminalEndpoint, lanHost: String?, choice: HomePathChoice): List<TerminalEndpoint> {
        val local = lanHost?.takeIf { it.isNotBlank() && it != relayed.host }?.let {
            relayed.copy(
                host = it,
                parent = null,
                kind = TerminalEndpoint.Kind.LOCAL_NETWORK,
                connectTimeoutMs = LOCAL_TIMEOUT_MS,
            )
        }
        return allowed(listOfNotNull(local) + relayed(relayed), choice)
    }

    /** The path a machine's row reports */
    fun pathInUse(choice: HomePathChoice, remembered: String?): HomePathChoice = when {
        choice != HomePathChoice.AUTOMATIC -> choice
        remembered == TerminalEndpoint.Kind.LOCAL_NETWORK.name -> HomePathChoice.LOCAL_NETWORK
        else -> HomePathChoice.THROUGH_VPS
    }

    /** Ways into a home network through a managed server */
    fun homeDetours(
        target: TerminalEndpoint,
        directID: String,
        fleet: List<Deployment>,
        endpoint: (Deployment, DeploymentNode) -> TerminalEndpoint,
        login: (Deployment, DeploymentNode) -> TerminalLogin?,
    ): List<TerminalEndpoint> {
        if (!isPrivate(target.host) || fleet.any { it.id == directID }) return emptyList()
        return fleet.flatMap { server ->
            server.nodes.drop(1)
                .filter { it.endpoint.host.isNotEmpty() }
                .flatMap { node -> detours(target, endpoint(server, node), node) { login(server, node) } }
        }
    }

    /** Into a network through the chosen machine */
    fun chosen(
        target: TerminalEndpoint,
        via: TerminalVia,
        fleet: List<Deployment>,
        endpoint: (Deployment, DeploymentNode) -> TerminalEndpoint,
        login: (Deployment, DeploymentNode) -> TerminalLogin?,
    ): List<TerminalEndpoint> {
        val server = fleet.firstOrNull { it.id == via.server } ?: return emptyList()
        val node = via.node?.let { id -> server.nodes.firstOrNull { it.id == id } } ?: server.nodes.firstOrNull()
        if (node == null || node.endpoint.host.isEmpty()) return emptyList()
        val machine = endpoint(server, node)
        if (machine.parent != null) return detours(target, machine, node) { login(server, node) }
        val jumpLogin = login(server, node) ?: return emptyList()
        return listOf(
            target.copy(
                parent = TerminalEndpoint.Hop(machine.host, machine.port, machine.pinnedHostKey, jumpLogin),
                kind = TerminalEndpoint.Kind.RELAY,
            ),
        )
    }

    /** Every managed machine with an address, by title */
    fun viaChoices(fleet: List<Deployment>): List<Pair<TerminalVia, String>> =
        fleet.filterNot { com.skaymer.gryonixnexus.app.servers.DemoDeployments.isDemoID(it.id) }.flatMap { server ->
            server.nodes.withIndex().filter { it.value.endpoint.host.isNotEmpty() }.map { (index, node) ->
                val via = TerminalVia(server.id, node.id.takeIf { index > 0 })
                val machine = node.name.ifEmpty { node.endpoint.host }
                via to if (index == 0) server.name else "${server.name} → $machine"
            }
        }

    /** What the screen calls a route */
    @androidx.annotation.StringRes
    fun titleRes(kind: TerminalEndpoint.Kind): Int = when (kind) {
        TerminalEndpoint.Kind.DIRECT -> com.skaymer.gryonixnexus.R.string.terminal_route_direct
        TerminalEndpoint.Kind.LOCAL_NETWORK -> com.skaymer.gryonixnexus.R.string.terminal_route_local
        TerminalEndpoint.Kind.RELAY -> com.skaymer.gryonixnexus.R.string.terminal_route_relay
        TerminalEndpoint.Kind.TUNNEL_ADDRESS -> com.skaymer.gryonixnexus.R.string.terminal_route_vpn
        TerminalEndpoint.Kind.FALLBACK_ADDRESS -> com.skaymer.gryonixnexus.R.string.terminal_route_fallback
    }

    /** Each tried way and why it failed */
    fun describe(
        failure: Exception,
        routes: List<TerminalEndpoint>,
        title: (TerminalEndpoint.Kind) -> String,
        hint: String,
    ): String {
        fun line(route: TerminalEndpoint, reason: String) = "${title(route.kind)} (${route.summary}): $reason"
        if (failure is com.skaymer.gryonixnexus.transport.TerminalRoutesFailed) {
            return failure.attempts.joinToString("\n") { (route, reason) -> line(route, reason) }
        }
        val reason = failure.message ?: failure::class.simpleName.orEmpty()
        val only = routes.singleOrNull() ?: return reason
        val text = line(only, reason)
        return if (only.hops.isEmpty() && isPrivate(only.host)) "$text\n$hint" else text
    }

    /** The home machine itself, or a neighbour it reaches */
    private fun detours(
        target: TerminalEndpoint,
        home: TerminalEndpoint,
        node: DeploymentNode,
        login: () -> TerminalLogin?,
    ): List<TerminalEndpoint> {
        val relay = home.parent ?: return emptyList()
        if (names(node, target.host)) {
            return relayed(home.copy(pinnedHostKey = target.pinnedHostKey))
        }
        val homeLogin = login() ?: return emptyList()
        return listOf(
            target.copy(
                parent = TerminalEndpoint.Hop(home.host, home.port, home.pinnedHostKey, homeLogin),
                outer = listOf(relay),
                kind = TerminalEndpoint.Kind.RELAY,
            ),
        )
    }

    /** Whether a typed address means this machine */
    fun names(node: DeploymentNode, typed: String): Boolean {
        val wanted = bare(typed)
        return wanted.isNotEmpty() && listOf(node.endpoint.host, node.name).map(::bare).contains(wanted)
    }

    /** Lower case, without the `.local` suffix */
    private fun bare(address: String): String = address.trim().lowercase().removeSuffix(".local")

    fun memoryKey(deploymentID: String, nodeID: String?): String =
        "terminal.route.$deploymentID.${nodeID ?: "entry"}"

    /** The route that worked last goes first */
    fun ordered(routes: List<TerminalEndpoint>, remembered: String?): List<TerminalEndpoint> {
        val kind = TerminalEndpoint.Kind.entries.firstOrNull { it.name == remembered } ?: return routes
        val index = routes.indexOfFirst { it.kind == kind }
        if (index <= 0) return routes
        return listOf(routes[index]) + routes.filterIndexed { at, _ -> at != index }
    }

    /** Addresses only a tunnel or the home network reaches */
    fun isPrivate(host: String): Boolean {
        val parts = host.split(".").mapNotNull { it.toIntOrNull() }
        if (parts.size == 4) {
            val (first, second) = parts
            return first == 10 ||
                (first == 192 && second == 168) ||
                (first == 169 && second == 254) ||
                (first == 172 && second in 16..31) ||
                (first == 100 && second in 64..127)
        }
        val lower = host.lowercase()
        val uniqueLocal = lower.contains(":") && (lower.startsWith("fd") || lower.startsWith("fc"))
        return uniqueLocal || lower.endsWith(".local")
    }
}

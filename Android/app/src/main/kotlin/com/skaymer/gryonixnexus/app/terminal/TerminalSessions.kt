package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.servers.ServerAccessStore
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.BastionHop
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HomePathChoice
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerAccessOptions
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import com.skaymer.gryonixnexus.transport.TerminalEvent
import com.skaymer.gryonixnexus.transport.TerminalLogin
import com.skaymer.gryonixnexus.transport.TerminalSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow

class TerminalSessions(
    private val store: SecretStore,
    private val settings: SettingsStore? = null,
    private val fleet: () -> List<Deployment> = { emptyList() },
    /** The machine a saved connection goes through */
    private val via: (String) -> TerminalVia? = { null },
    /** The tunnel a terminal can turn on when nothing answers */
    val vpn: TerminalVpn? = null,
) {
    /** A shell that remembers a first-seen host key through [onPin] */
    fun transport(
        routes: List<TerminalEndpoint>,
        login: TerminalLogin,
        onPin: (String, String) -> Unit,
    ): TerminalTransport = Live(TerminalSession(routes, login, onPinHostKey = onPin))

    /** Every way to this machine, last working one first */
    fun routes(deployment: Deployment, node: DeploymentNode): List<TerminalEndpoint> {
        val primary = endpoint(deployment, node)
        val routes = when {
            primary.parent != null -> TerminalRoutes.behindVPS(primary, lanHost(deployment, node), homePath(deployment))
            node.id != deployment.nodes.firstOrNull()?.id -> listOf(primary)
            else -> {
                val access = access(deployment)
                val fallback = access.fallback?.takeIf { it.isUsable }?.let { chosen ->
                    val address = chosen.endpoint(deployment.entry)
                    primary.copy(host = address.host, port = address.port, parent = hop(chosen.bastion, deployment))
                }
                val chosen = via(deployment.id)?.let { chosenRoutes(it, primary) }
                val detours = chosen ?: homeDetours(deployment, primary)
                val wait = if (detours.isEmpty()) primary.connectTimeoutMs else TerminalRoutes.LOCAL_TIMEOUT_MS
                val entry = TerminalRoutes.entry(primary.copy(parent = hop(access.bastion, deployment), connectTimeoutMs = wait),
                    fallback)
                if (!chosen.isNullOrEmpty()) return chosen + entry
                entry + detours
            }
        }
        return TerminalRoutes.ordered(routes, settings?.string(memoryKey(deployment, node)))
    }

    private fun lanHost(deployment: Deployment, node: DeploymentNode): String? =
        DeploymentSecrets(store, deployment.id).homeAddress().takeIf { node.legacySlot == DeploymentNode.LegacySlot.HOME }

    private fun homePath(deployment: Deployment): HomePathChoice = DeploymentSecrets(store, deployment.id).homePath()

    /** Which path a machine behind the VPS is reached by */
    fun pathInUse(deployment: Deployment, node: DeploymentNode): HomePathChoice =
        TerminalRoutes.pathInUse(homePath(deployment), settings?.string(memoryKey(deployment, node)))

    /** Through the machine a saved connection names */
    private fun chosenRoutes(via: TerminalVia, typed: TerminalEndpoint): List<TerminalEndpoint> =
        TerminalRoutes.chosen(
            target = typed,
            via = via,
            fleet = fleet().filterNot { DemoDeployments.isDemoID(it.id) },
            endpoint = ::endpoint,
            login = ::appLogin,
        )

    /** A typed address, reached through a server's home network */
    private fun homeDetours(deployment: Deployment, typed: TerminalEndpoint): List<TerminalEndpoint> =
        TerminalRoutes.homeDetours(
            target = typed,
            directID = deployment.id,
            fleet = fleet().filterNot { DemoDeployments.isDemoID(it.id) },
            endpoint = ::endpoint,
            login = ::appLogin,
        )

    fun remember(deployment: Deployment, node: DeploymentNode, route: TerminalEndpoint) {
        settings?.setString(memoryKey(deployment, node), route.kind.name)
    }

    private fun memoryKey(deployment: Deployment, node: DeploymentNode): String =
        TerminalRoutes.memoryKey(deployment.id, node.id.takeIf { it != deployment.nodes.firstOrNull()?.id })

    private fun access(deployment: Deployment): ServerAccessOptions =
        settings?.let { ServerAccessStore.options(it, deployment.id) } ?: ServerAccessOptions.NONE

    /** A configured jump host, as the terminal signs in */
    private fun hop(bastion: BastionHop?, deployment: Deployment): TerminalEndpoint.Hop? {
        if (bastion?.isUsable != true) return null
        val secrets = DeploymentSecrets(store, deployment.id)
        val server = bastion.fleetServerID?.let { id -> fleet().firstOrNull { it.id == id } }
        if (server != null) {
            val own = DeploymentSecrets(store, server.id)
            val password = own.password(SSHHostID.VPS)
            val seed = own.identitySeed() ?: secrets.identitySeed() ?: return null
            return TerminalEndpoint.Hop(
                host = server.entry.host,
                port = server.entry.port,
                pinnedHostKey = own.hostKeyPin(DeploymentNode.LegacySlot.VPS),
                login = TerminalLogin(
                    server.entry.user,
                    password?.let { TerminalLogin.Secret.Password(it) } ?: TerminalLogin.Secret.PrivateKeySeed(seed),
                ),
            )
        }
        val manual = bastion.manual?.takeIf { it.isValid } ?: return null
        val seed = secrets.identitySeed() ?: return null
        return TerminalEndpoint.Hop(
            host = manual.host,
            port = manual.port,
            pinnedHostKey = secrets.bastionHostKeyPin("${manual.host}:${manual.port}"),
            login = TerminalLogin(manual.user, TerminalLogin.Secret.PrivateKeySeed(seed)),
        )
    }

    fun endpoint(deployment: Deployment, node: DeploymentNode): TerminalEndpoint {
        val secrets = DeploymentSecrets(store, deployment.id)
        return TerminalViewModel.endpoint(
            deployment = deployment,
            node = node,
            pin = { machine ->
                machine.legacySlot?.let { secrets.hostKeyPin(it) } ?: secrets.hostKeyPin(machine.id)
            },
            appLogin = { hop -> appLogin(deployment, hop) },
        )
    }

    /** This server's saved logins */
    val accessoryKeys: AccessoryLayoutStore by lazy { AccessoryLayoutStore(settings) }

    val appearance: TerminalAppearanceStore by lazy { TerminalAppearanceStore(settings) }

    fun savedSessions(): SavedTerminalSessionsStore? = settings?.let(::SavedTerminalSessionsStore)

    /** Shells that outlive one screen, several per server */
    val shells: TerminalShells by lazy { TerminalShells() }

    /** A shell model for one machine, not yet dialled */
    fun shellModel(
        scope: CoroutineScope,
        deployment: Deployment,
        node: DeploymentNode,
        startupInput: ByteArray?,
        notices: (TerminalViewModel.Notice) -> String,
    ): TerminalViewModel = TerminalViewModel(
        scope = scope,
        sessions = { chosen, signIn ->
            when {
                DemoDeployments.isDemoID(deployment.id) -> DemoTerminalTransport(signIn.username, deployment.name)
                !LicenseGate.unlocked -> LockedTerminalTransport(deployment.id).also { LicensePrompt.allow() }
                else -> transport(chosen, signIn) { host, key -> pin(deployment, host, key) }
            }
        },
        notices = notices,
        onConnected = { route -> remember(deployment, node, route) },
        startupInput = startupInput,
        queuedInput = { TerminalScriptQueue.take(deployment.id) },
    )

    fun profiles(deployment: Deployment): TerminalProfileStore = TerminalProfileStore(store, deployment.id)

    /** What a saved login signs in with */
    fun login(deployment: Deployment, profile: TerminalProfile): TerminalLogin = TerminalLogin(
        username = profile.username,
        secret = if (profile.usesAppKey) TerminalLogin.Secret.PrivateKeySeed(appKeySeed(deployment))
        else TerminalLogin.Secret.Password(profile.password),
    )

    private fun chosenKey(deployment: Deployment, node: DeploymentNode) = "terminal-machine-user-${deployment.id}-${node.id}"

    /** The account chosen for a machine, or the app's own */
    fun chosenUser(deployment: Deployment, node: DeploymentNode): String =
        store.string(chosenKey(deployment, node))?.takeIf { it.isNotEmpty() } ?: node.endpoint.user

    fun choose(deployment: Deployment, node: DeploymentNode, user: String) {
        if (user == node.endpoint.user) store.deleteSecret(chosenKey(deployment, node)) else store.setString(chosenKey(deployment, node), user)
    }

    /** One login per machine, as its chosen account */
    fun machineLogins(deployment: Deployment): List<TerminalProfile> =
        deployment.nodes.filter { it.endpoint.host.isNotEmpty() && it.endpoint.user.isNotEmpty() }.mapNotNull { node ->
            val chosen = chosenUser(deployment, node)
            if (chosen != node.endpoint.user) {
                if (!hasAppKey(deployment)) return@mapNotNull null
                return@mapNotNull TerminalProfile("${node.id}/$chosen", chosen, node.id.toString(), usesAppKey = true)
            }
            val password = if (deployment.usesPasswordAuth) {
                DeploymentSecrets(store, deployment.id).password(node.sshHost) ?: return@mapNotNull null
            } else ""
            if (!deployment.usesPasswordAuth && !hasAppKey(deployment)) return@mapNotNull null
            TerminalProfile(
                id = node.id.toString(),
                username = node.endpoint.user,
                nodeID = node.id.toString(),
                usesAppKey = !deployment.usesPasswordAuth,
                password = password,
            )
        }

    fun hasAppKey(deployment: Deployment): Boolean =
        DeploymentSecrets(store, deployment.id).identitySeed()?.size == SEED_LENGTH

    /** The app's own key */
    fun appKeySeed(deployment: Deployment): ByteArray =
        DeploymentSecrets(store, deployment.id).identitySeed() ?: ByteArray(0)

    fun pin(deployment: Deployment, host: String, key: String) {
        val secrets = DeploymentSecrets(store, deployment.id)
        val node = deployment.nodes.firstOrNull { it.endpoint.host == host }
            ?: deployment.nodes.firstOrNull()?.takeIf { host == fallbackHost(deployment) }
        if (node != null) {
            node.legacySlot?.let { secrets.setHostKeyPin(key, it) } ?: secrets.setHostKeyPin(key, node.id)
            return
        }
        pinBastion(deployment, host, key)
    }

    private fun fallbackHost(deployment: Deployment): String? =
        access(deployment).fallback?.takeIf { it.isUsable }?.endpoint(deployment.entry)?.host

    /** A jump host's key, kept where the dashboard keeps it */
    private fun pinBastion(deployment: Deployment, host: String, key: String) {
        val access = access(deployment)
        for (bastion in listOfNotNull(access.bastion, access.fallback?.bastion)) {
            val server = bastion.fleetServerID?.let { id -> fleet().firstOrNull { it.id == id } }
            if (server != null && server.entry.host == host) {
                DeploymentSecrets(store, server.id).setHostKeyPin(key, DeploymentNode.LegacySlot.VPS)
                return
            }
            val manual = bastion.manual
            if (server == null && manual != null && manual.host == host) {
                DeploymentSecrets(store, deployment.id).setBastionHostKeyPin(key, "${manual.host}:${manual.port}")
                return
            }
        }
    }

    private fun appLogin(deployment: Deployment, hop: DeploymentNode): TerminalLogin? {
        val secrets = DeploymentSecrets(store, deployment.id)
        val password = secrets.password(hop.sshHost)
        val secret = when {
            deployment.usesPasswordAuth && !password.isNullOrEmpty() ->
                TerminalLogin.Secret.Password(password)
            else -> secrets.identitySeed()?.let { TerminalLogin.Secret.PrivateKeySeed(it) }
        } ?: return null
        return TerminalLogin(username = hop.endpoint.user, secret = secret)
    }

    private class Live(private val session: TerminalSession) : TerminalTransport {
        override val output: Flow<TerminalEvent> get() = session.output
        override val connectedRoute: TerminalEndpoint? get() = session.connectedRoute
        override suspend fun start(columns: Int, rows: Int) = session.start(columns, rows)
        override suspend fun send(data: ByteArray) = session.send(data)
        override suspend fun resize(columns: Int, rows: Int) = session.resize(columns, rows)
        override suspend fun close() = session.close()
    }

    private companion object {
        /** An ed25519 seed, and the only length one can be */
        const val SEED_LENGTH = 32
    }
}

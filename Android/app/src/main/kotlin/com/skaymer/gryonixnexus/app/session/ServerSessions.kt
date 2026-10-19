package com.skaymer.gryonixnexus.app.session

import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.transport.SSHClients
import com.skaymer.gryonixnexus.transport.SSHConnectionSettings
import com.skaymer.gryonixnexus.transport.SSHJCommandRunner
import com.skaymer.gryonixnexus.transport.TOFUHostKeyVerifier
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import net.schmizz.sshj.SSHClient

class ServerSessions(
    private val store: SecretStore,
    private val settingsStore: com.skaymer.gryonixnexus.app.shell.SettingsStore? = null,
    private val fleet: () -> List<Deployment> = { emptyList() },
) {
    private val _onFallback = kotlinx.coroutines.flow.MutableStateFlow<Set<String>>(emptySet())
    val onFallback: kotlinx.coroutines.flow.StateFlow<Set<String>> = _onFallback

    private val bastions = java.util.concurrent.ConcurrentHashMap<String, SSHClient>()

    /** The deployment fields the session is actually BUILT from */
    private data class Fingerprint(
        val host: String,
        val port: Int,
        val user: String,
        val homeWGAddress: String?,
        /** The machines and where to reach them */
        val machines: Map<SSHHostID, HostEndpoint>,
        val usesPasswordAuth: Boolean,
    ) {
        constructor(deployment: Deployment) : this(
            host = deployment.entry.host,
            port = deployment.entry.port,
            user = deployment.entry.user,
            homeWGAddress = deployment.homeWGAddress,
            machines = deployment.nodes.associate { it.sshHost to it.endpoint },
            usesPasswordAuth = deployment.usesPasswordAuth,
        )
    }

    private class Live(val fingerprint: Fingerprint, val runner: SSHJCommandRunner)

    private val live = mutableMapOf<String, Live>()
    private val lock = Mutex()

    fun settings(deployment: Deployment): SSHConnectionSettings {
        val secrets = DeploymentSecrets(store, deployment.id)
        val passwords = if (deployment.usesPasswordAuth) {
            buildMap {
                secrets.password(SSHHostID.VPS)?.let { put(SSHHostID.VPS, it) }
                if (deployment.hasHomeHost) {
                    secrets.password(SSHHostID.HOME)?.let { put(SSHHostID.HOME, it) }
                }
                deployment.nodes.filter { it.legacySlot == null }.forEach { node ->
                    secrets.password(node.sshHost)?.let { put(node.sshHost, it) }
                }
            }
        } else {
            emptyMap()
        }
        return SSHConnectionSettings(
            vpsHost = deployment.entry.host,
            vpsPort = deployment.entry.port,
            username = deployment.entry.user,
            homeHost = deployment.homeWGAddress.orEmpty(),
            privateKeySeed = secrets.identitySeed() ?: ByteArray(0),
            passwords = passwords,
            pinnedVPSHostKey = secrets.hostKeyPin(DeploymentNode.LegacySlot.VPS),
            pinnedHomeHostKey = secrets.hostKeyPin(DeploymentNode.LegacySlot.HOME),
            additionalNodes = SSHConnectionSettings.additionalNodes(deployment) { host ->
                when (val kind = host.kind) {
                    is SSHHostID.Kind.Slot -> secrets.hostKeyPin(kind.slot)
                    is SSHHostID.Kind.Node -> secrets.hostKeyPin(kind.id)
                }
            },
        )
    }

    /** A runner for this deployment */
    suspend fun runner(deployment: Deployment): SSHJCommandRunner = lock.withLock {
        val fingerprint = Fingerprint(deployment)
        live[deployment.id]?.let { existing ->
            if (existing.fingerprint == fingerprint) return@withLock existing.runner
            existing.runner.disconnect()
        }
        val fresh = build(deployment)
        live[deployment.id] = Live(fingerprint, fresh)
        fresh
    }

    /** Let go of this server's session */
    suspend fun release(deploymentID: String) {
        lock.withLock { live.remove(deploymentID) }
    }

    suspend fun disconnect(deploymentID: String) {
        lock.withLock { live.remove(deploymentID) }?.runner?.disconnect()
    }

    suspend fun disconnectAll() {
        lock.withLock {
            live.values.forEach { it.runner.disconnect() }
            live.clear()
        }
    }

    /** A session of its OWN, kept by nobody */
    fun detached(deployment: Deployment): SSHJCommandRunner = build(deployment)

    private fun build(deployment: Deployment): SSHJCommandRunner {
        com.skaymer.gryonixnexus.app.licensing.LicenseGate.check(deployment)
        val settings = settings(deployment)
        val secrets = DeploymentSecrets(store, deployment.id)
        return SSHJCommandRunner(
            settings = settings,
            onPinHostKey = { host, key ->
                when (val kind = host.kind) {
                    is SSHHostID.Kind.Slot -> secrets.setHostKeyPin(key, kind.slot)
                    is SSHHostID.Kind.Node -> secrets.setHostKeyPin(key, kind.id)
                }
            },
            connect = { address, host -> dial(address, host, settings, deployment, secrets) }
        )
    }

    private suspend fun dial(
        address: SSHConnectionSettings.Route.Address,
        host: SSHHostID,
        settings: SSHConnectionSettings,
        deployment: Deployment,
        secrets: DeploymentSecrets,
    ): SSHClient = withContext(Dispatchers.IO) {
        val access = settingsStore?.let {
            com.skaymer.gryonixnexus.app.servers.ServerAccessStore.options(it, deployment.id)
        }
        val hop = access?.bastion
        try {
            val client = dialThrough(address.host, address.port, hop, host, settings, deployment, secrets)
            if (host == SSHHostID.VPS) markFallback(deployment.id, false)
            return@withContext client
        } catch (failure: Exception) {
            val fallback = access?.fallback?.takeIf { it.isUsable && host == SSHHostID.VPS }
                ?: throw failure
            if (!machineDidNotAnswer(failure)) throw failure
            val endpoint = fallback.endpoint(deployment.entry)
            val client = dialThrough(
                endpoint.host, endpoint.port, fallback.bastion ?: hop,
                host, settings, deployment, secrets,
            )
            markFallback(deployment.id, true)
            return@withContext client
        }
    }

    /** Did the machine answer at all? */
    private fun machineDidNotAnswer(failure: Throwable): Boolean {
        var cause: Throwable? = failure
        while (cause != null) {
            when (cause) {
                is java.net.ConnectException,
                is java.net.NoRouteToHostException,
                is java.net.PortUnreachableException,
                is java.net.UnknownHostException,
                is java.net.SocketTimeoutException,
                -> return true
            }
            cause = cause.cause?.takeIf { it !== cause }
        }
        return false
    }

    private fun markFallback(deploymentID: String, on: Boolean) {
        _onFallback.value = if (on) _onFallback.value + deploymentID else _onFallback.value - deploymentID
    }

    /** One dial, optionally through a jump host */
    private fun dialThrough(
        host: String,
        port: Int,
        hop: com.skaymer.gryonixnexus.servercontrol.BastionHop?,
        hostID: SSHHostID,
        settings: SSHConnectionSettings,
        deployment: Deployment,
        secrets: DeploymentSecrets,
    ): SSHClient {
        if (hop == null || !hop.isUsable) {
            return SSHClients.redialing { dialDirect(host, port, hostID, settings, deployment, secrets) }
        }
        val through = bastionClient(hop, deployment, secrets)
        return dialDirect(host, port, hostID, settings, deployment, secrets, via = through)
    }

    /** The session to a jump host, opened once and shared */
    private fun bastionClient(
        hop: com.skaymer.gryonixnexus.servercontrol.BastionHop,
        deployment: Deployment,
        secrets: DeploymentSecrets,
    ): SSHClient {
        val endpoint = hop.fleetServerID?.let { id ->
            fleet().firstOrNull { it.id == id }?.entry
        } ?: hop.manual ?: throw IllegalStateException("the bastion names no host")
        val key = "${endpoint.host}:${endpoint.port}"
        bastions[key]?.let { if (it.isConnected) return it else bastions.remove(key) }

        val bastionSecrets = hop.fleetServerID?.let { DeploymentSecrets(store, it) }
        val client = SSHClients.create()
        client.addHostKeyVerifier(
            TOFUHostKeyVerifier(
                hostLabel = endpoint.host,
                pinnedKey = bastionSecrets?.hostKeyPin(DeploymentNode.LegacySlot.VPS)
                    ?: secrets.bastionHostKeyPin(key),
                onPin = { presented ->
                    if (bastionSecrets != null) {
                        bastionSecrets.setHostKeyPin(presented, DeploymentNode.LegacySlot.VPS)
                    } else {
                        secrets.setBastionHostKeyPin(presented, key)
                    }
                },
            ),
        )
        proxySocket(deployment, endpoint.host, endpoint.port)?.let { socket ->
            client.socketFactory = object : javax.net.SocketFactory() {
                override fun createSocket() = socket
                override fun createSocket(host: String?, port: Int) = socket
                override fun createSocket(
                    host: String?,
                    port: Int,
                    localHost: java.net.InetAddress?,
                    localPort: Int,
                ) = socket
                override fun createSocket(host: java.net.InetAddress?, port: Int) = socket
                override fun createSocket(
                    host: java.net.InetAddress?,
                    port: Int,
                    localHost: java.net.InetAddress?,
                    localPort: Int,
                ) = socket
            }
        }
        SSHClients.signIn(client) {
            connect(endpoint.host, endpoint.port)
            val password = bastionSecrets?.password(SSHHostID.VPS)
            if (password != null) {
                authPassword(endpoint.user, password)
            } else {
                val seed = bastionSecrets?.identitySeed() ?: secrets.identitySeed() ?: ByteArray(0)
                authPublickey(endpoint.user, SSHJCommandRunner.keyProvider(seed))
            }
        }
        bastions[key] = client
        return client
    }

    private fun proxySocket(deployment: Deployment, address: String, port: Int): java.net.Socket? {
        val preferences = settingsStore ?: return null
        val access = com.skaymer.gryonixnexus.app.servers.ServerAccessStore
            .options(preferences, deployment.id)
        val profile = com.skaymer.gryonixnexus.app.servers.ProxyStore
            .profile(preferences, access.proxyID)
            ?.takeIf { it.isUsable } ?: return null
        val credentials = com.skaymer.gryonixnexus.app.servers.ProxyPasswords(store)
        val user = profile.username.trim()
        val password = credentials.password(profile.id).orEmpty()
        return when (profile.kind) {
            com.skaymer.gryonixnexus.servercontrol.ProxyProfile.Kind.SOCKS5 -> {
                if (user.isNotEmpty()) {
                    java.net.Authenticator.setDefault(object : java.net.Authenticator() {
                        override fun getPasswordAuthentication(): java.net.PasswordAuthentication? =
                            if (requestingHost.equals(profile.host, ignoreCase = true)) {
                                java.net.PasswordAuthentication(user, password.toCharArray())
                            } else {
                                null
                            }
                    })
                }
                java.net.Socket(
                    java.net.Proxy(
                        java.net.Proxy.Type.SOCKS,
                        java.net.InetSocketAddress(profile.host, profile.port),
                    ),
                ).apply {
                    connect(java.net.InetSocketAddress.createUnresolved(address, port), 20_000)
                }
            }

            com.skaymer.gryonixnexus.servercontrol.ProxyProfile.Kind.HTTP_CONNECT ->
                httpConnectSocket(profile.host, profile.port, address, port, user, password)
        }
    }

    private fun httpConnectSocket(
        proxyHost: String,
        proxyPort: Int,
        targetHost: String,
        targetPort: Int,
        user: String,
        password: String,
    ): java.net.Socket {
        val socket = java.net.Socket()
        socket.connect(java.net.InetSocketAddress(proxyHost, proxyPort), 20_000)
        val request = buildString {
            append("CONNECT $targetHost:$targetPort HTTP/1.1\r\n")
            append("Host: $targetHost:$targetPort\r\n")
            if (user.isNotEmpty()) {
                val token = android.util.Base64.encodeToString(
                    "$user:$password".toByteArray(),
                    android.util.Base64.NO_WRAP,
                )
                append("Proxy-Authorization: Basic $token\r\n")
            }
            append("Proxy-Connection: keep-alive\r\n\r\n")
        }
        socket.getOutputStream().write(request.toByteArray())
        socket.getOutputStream().flush()

        val reply = StringBuilder()
        val input = socket.getInputStream()
        while (!reply.endsWith("\r\n\r\n")) {
            val byte = input.read()
            if (byte < 0) {
                runCatching { socket.close() }
                throw java.io.IOException("the proxy closed the connection")
            }
            reply.append(byte.toChar())
        }
        val status = reply.lineSequence().firstOrNull().orEmpty()
        val code = status.split(" ").getOrNull(1)?.toIntOrNull() ?: 0
        if (code !in 200..299) {
            runCatching { socket.close() }
            throw java.io.IOException("the proxy refused: ${status.trim()}")
        }
        return socket
    }

    private fun dialDirect(
        address: String,
        port: Int,
        host: SSHHostID,
        settings: SSHConnectionSettings,
        deployment: Deployment,
        secrets: DeploymentSecrets,
        via: SSHClient? = null,
    ): SSHClient {
        val client = SSHClients.create()
        val kind = host.kind
        client.addHostKeyVerifier(
            TOFUHostKeyVerifier(
                hostLabel = deployment.name,
                pinnedKey = when (kind) {
                    is SSHHostID.Kind.Slot -> secrets.hostKeyPin(kind.slot)
                    is SSHHostID.Kind.Node -> secrets.hostKeyPin(kind.id)
                },
                onPin = { key ->
                    when (kind) {
                        is SSHHostID.Kind.Slot -> secrets.setHostKeyPin(key, kind.slot)
                        is SSHHostID.Kind.Node -> secrets.setHostKeyPin(key, kind.id)
                    }
                }
            )
        )
        val socket = if (via == null) proxySocket(deployment, address, port) else null
        if (socket != null) {
            client.socketFactory = object : javax.net.SocketFactory() {
                override fun createSocket() = socket
                override fun createSocket(host: String?, port: Int) = socket
                override fun createSocket(
                    host: String?,
                    port: Int,
                    localHost: java.net.InetAddress?,
                    localPort: Int,
                ) = socket
                override fun createSocket(host: java.net.InetAddress?, port: Int) = socket
                override fun createSocket(
                    address: java.net.InetAddress?,
                    port: Int,
                    localAddress: java.net.InetAddress?,
                    localPort: Int,
                ) = socket
            }
        }
        return SSHClients.signIn(client) {
            if (via != null) connectVia(via.newDirectConnection(address, port)) else connect(address, port)
            SSHJCommandRunner.authenticate(this, settings, host)
        }
    }
}

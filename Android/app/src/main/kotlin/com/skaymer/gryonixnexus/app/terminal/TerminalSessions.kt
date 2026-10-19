package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import com.skaymer.gryonixnexus.transport.TerminalEvent
import com.skaymer.gryonixnexus.transport.TerminalLogin
import com.skaymer.gryonixnexus.transport.TerminalSession
import kotlinx.coroutines.flow.Flow

class TerminalSessions(private val store: SecretStore) {
    /** A shell that remembers a first-seen host key through [onPin] */
    fun transport(
        endpoint: TerminalEndpoint,
        login: TerminalLogin,
        onPin: (String, String) -> Unit,
    ): TerminalTransport = Live(TerminalSession(endpoint, login, onPinHostKey = onPin))

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

    fun hasAppKey(deployment: Deployment): Boolean =
        DeploymentSecrets(store, deployment.id).identitySeed()?.size == SEED_LENGTH

    /** The app's own key */
    fun appKeySeed(deployment: Deployment): ByteArray =
        DeploymentSecrets(store, deployment.id).identitySeed() ?: ByteArray(0)

    fun pin(deployment: Deployment, host: String, key: String) {
        val secrets = DeploymentSecrets(store, deployment.id)
        val node = deployment.nodes.firstOrNull { it.endpoint.host == host } ?: return
        node.legacySlot?.let { secrets.setHostKeyPin(key, it) } ?: secrets.setHostKeyPin(key, node.id)
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

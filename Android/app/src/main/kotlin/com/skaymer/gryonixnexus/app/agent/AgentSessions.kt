package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentcontrol.AgentChannelGate
import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.transport.SSHAgentTransport
import com.skaymer.gryonixnexus.transport.SSHJCommandRunner
import com.skaymer.gryonixnexus.transport.SshjBridgeChannelFactory

class AgentSessions(
    private val runners: suspend (Deployment) -> SSHJCommandRunner,
    /** This installation's id, sent on every RPC */
    private val deviceUID: () -> String = { "" },
    /** Runs on every client opened for a deployment */
    private val onOpened: suspend (Deployment, SSHJCommandRunner, AgentClient) -> Unit = { _, _, _ -> },
) {
    /** The client for one deployment's agent */
    suspend fun client(deployment: Deployment, host: SSHHostID? = null): AgentClient {
        val runner = runners(deployment)
        val opened = client(runner, host ?: deployment.servicesHost)
        onOpened(deployment, runner, opened)
        return opened
    }

    suspend fun client(runner: SSHJCommandRunner, host: SSHHostID): AgentClient {
        val connection = runner.sshClient(host)
        return AgentClient(
            transport = SSHAgentTransport(
                channels = SshjBridgeChannelFactory(connection),
                bridgeCommand = AgentBootstrapSections.BRIDGE_COMMAND,
                deviceUID = deviceUID(),
            )
        )
    }

    /** The gate every agent call on one server goes under */
    fun gate(deployment: Deployment): AgentChannelGate =
        AgentChannelGate.shared(deployment.id)
}

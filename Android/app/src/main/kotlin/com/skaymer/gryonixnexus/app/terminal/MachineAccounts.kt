package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SshUserAccess

/** A machine's accounts, and the app's key put on one */
class MachineAccounts(
    private val operations: suspend (Deployment, DeploymentNode) -> AgentSecurityOperations,
    private val publicKey: (Deployment) -> String,
) {
    /** Whether this machine's agent can list its accounts */
    fun lists(deployment: Deployment, node: DeploymentNode): Boolean =
        deployment.usesAgent && node.sshHost in deployment.agentHosts

    suspend fun list(deployment: Deployment, node: DeploymentNode): List<SshUserAccess> {
        val answer = operations(deployment, node).sshUsers(node.endpoint.user, publicKey(deployment))
        return if (answer.isKnown) answer.users else emptyList()
    }

    /** Adds the app's key to the account if missing */
    suspend fun prepare(deployment: Deployment, node: DeploymentNode, user: String, known: List<SshUserAccess>): List<SshUserAccess> {
        if (user == node.endpoint.user || known.firstOrNull { it.name == user }?.appKeyPresent == true) return known
        return operations(deployment, node).authorizeAppKey(user, node.endpoint.user, publicKey(deployment)).users
    }
}

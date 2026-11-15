package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.AppKeyRevocation
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import kotlinx.coroutines.CancellationException
import kotlin.time.Duration.Companion.seconds

/** Takes this app's keys off a server before forgetting it */
class ServerRemoval(
    private val runner: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (String) -> Unit,
    private val appKey: (String) -> String?,
    private val removeOwnDevices: suspend (Deployment) -> List<String>,
) {
    /** One machine and what else lets someone in */
    data class MachineCheck(val node: DeploymentNode, val check: AppKeyRevocation.AccessCheck?)

    /** Reads every machine; throws when none answers */
    suspend fun check(deployment: Deployment): List<MachineCheck> {
        val body = appKey(deployment.id)?.let(AppKeyRevocation::keyBody) ?: return emptyList()
        val session = runner(deployment)
        var firstError: Exception? = null
        val checks = deployment.nodes.map { node ->
            try {
                val result = session.run(AppKeyRevocation.checkScript(body), node.sshHost, 30.seconds)
                MachineCheck(node, AppKeyRevocation.parse(result.stdout))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                if (firstError == null) firstError = failure
                MachineCheck(node, null)
            }
        }
        firstError?.let { if (checks.all { check -> check.check == null }) throw it }
        return checks
    }

    /** Removes own VPN entries and the key, returns failures */
    suspend fun revoke(deployment: Deployment, keepKeyOn: Set<String>): List<String> {
        val failures = removeOwnDevices(deployment).toMutableList()
        val body = appKey(deployment.id)?.let(AppKeyRevocation::keyBody)
        if (body != null) {
            val session = runCatching { runner(deployment) }.getOrNull()
            for (node in AppKeyRevocation.removalOrder(deployment.nodes)) {
                if (node.id in keepKeyOn) continue
                val result = runCatching { session?.run(AppKeyRevocation.removeScript(body), node.sshHost, 30.seconds) }
                    .getOrNull()
                if (result?.succeeded != true) failures += node.name.ifEmpty { deployment.name }
            }
        }
        release(deployment.id)
        return failures
    }
}

package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.recipe.InstallReportFacts
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.DKIMRecordParser
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.time.Duration.Companion.seconds

class InstallReportImport(
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val reports: (Deployment) -> InstallReportStore,
    private val onDomainFound: (Deployment, String) -> Unit = { _, _ -> },
) {
    private val tried = mutableSetOf<String>()

    /** Ask every machine of one deployment */
    suspend fun importIfNeeded(deployment: Deployment): Boolean {
        val store = reports(deployment)
        val stored = store.load().associate { it.host to it.text }
        var wrote = false
        var statedDomain = false
        for ((key, host) in hosts(deployment)) {
            val marker = "${deployment.id}|$key"
            if (marker in tried) continue
            tried += marker
            val text = read(deployment, host) ?: continue
            if (text != stored[key]) {
                store.save(key, text)
                wrote = true
            }
            InstallReportFacts.domain(text)?.let {
                statedDomain = true
                onDomainFound(deployment, it)
            }
        }
        if (!statedDomain) {
            for (text in stored.values) {
                InstallReportFacts.domain(text)?.let {
                    statedDomain = true
                    onDomainFound(deployment, it)
                }
                if (statedDomain) break
            }
        }
        return wrote
    }

    fun forget() = tried.clear()

    private suspend fun read(deployment: Deployment, host: SSHHostID): String? = try {
        val runner = runners(deployment)
        val result = runner.run(CommandCatalog.INSTALL_REPORT, host, 30.seconds)
        val text = result.stdout.trim()
        if (text.isEmpty()) null else DKIMRecordParser.stripMarkers(result.stdout)
    } catch (_: Throwable) {
        null
    }

    companion object {
        fun hosts(deployment: Deployment): List<Pair<String, SSHHostID>> =
            deployment.nodes.map { node -> key(node, deployment) to node.sshHost }

        /** The name one machine's report is filed under */
        private fun key(node: DeploymentNode, deployment: Deployment): String =
            when (node.legacySlot) {
                DeploymentNode.LegacySlot.VPS -> if (deployment.hasRelayIngress) "vps" else "single"
                DeploymentNode.LegacySlot.HOME -> "home"
                null -> node.id
            }
    }
}

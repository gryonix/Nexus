package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.agentcontrol.AgentInstallContext
import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.app.agent.AgentBootstrapOperations
import com.skaymer.gryonixnexus.app.agent.AgentSessions
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.servers.TunnelSetup
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.GeneratedBundle
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CoroutineScope

class InstallRegistry(
    private val scope: CoroutineScope,
    private val sessions: InstallSessions,
    /** Where each machine's report is filed, per deployment */
    private val reports: (Deployment) -> InstallReportStore,
    private val agent: Agent? = null,
) {
    class Agent(
        val sessions: AgentSessions,
        val sources: AgentBootstrapOperations.Sources,
        val context: (Deployment) -> AgentInstallContext,
        val persistUsesAgent: (Deployment) -> Unit,
        val tunnel: TunnelSetup? = null,
    )

    private class Entry(val deploymentID: String, val fingerprint: Int, val model: InstallViewModel)

    private var current: Entry? = null

    fun model(
        deployment: Deployment,
        bundle: GeneratedBundle,
        appPublicKey: String?,
        homeAddress: String = "",
    ): InstallViewModel {
        val fingerprint = fingerprint(bundle)
        current?.let { entry ->
            if (entry.deploymentID == deployment.id && entry.fingerprint == fingerprint) {
                return entry.model
            }
        }
        val model = InstallViewModel(
            scope = scope,
            deployment = deployment,
            bundle = bundle,
            appPublicKey = appPublicKey,
            runners = { target ->
                if (LicenseGate.unlocked) {
                    sessions.runner(deployment.id, target)
                } else {
                    DemoInstallRunner(deployment.services.map { it.rawValue }, deployment.domain)
                }
            },
            saveReport = { host, text -> reports(deployment).save(host, text) },
            agentSessions = agent?.sessions,
            agentSources = agent?.sources,
            agentContext = agent?.context,
            persistUsesAgent = agent?.persistUsesAgent ?: {},
            homeAddress = homeAddress,
            tunnel = agent?.tunnel,
        )
        current = Entry(deployment.id, fingerprint, model)
        return model
    }

    private companion object {
        /** The scripts, and only the scripts */
        fun fingerprint(bundle: GeneratedBundle): Int =
            bundle.artifacts
                .filter { it.kind == ArtifactKind.SHELL_SCRIPT }
                .fold(7) { hash, artifact ->
                    31 * (31 * hash + artifact.fileName.hashCode()) + artifact.contents.hashCode()
                }
    }
}

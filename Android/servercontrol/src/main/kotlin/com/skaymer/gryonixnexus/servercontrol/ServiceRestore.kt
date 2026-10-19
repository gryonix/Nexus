package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ManagedService

interface ServiceRestoreManaging {
    /** Restores this service from [archivePath], streaming the wrapper's output */
    suspend fun restore(
        service: ManagedService,
        archivePath: String,
        passphrase: String?,
        onChunk: (String) -> Unit = {},
    ): String
}

/** Which implementation a deployment's RESTORES go through */
object RestoreRouting {
    fun route(usesAgent: Boolean, agentTransportAvailable: Boolean): ServiceControlRoute =
        ServiceControlRouting.route(usesAgent, agentTransportAvailable)
}

/** The SSH implementation: the existing catalog-derived command, unchanged */
class SSHServiceRestore(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
    private val language: AppLanguage = AppLanguage.EN,
) : ServiceRestoreManaging {
    override suspend fun restore(
        service: ManagedService,
        archivePath: String,
        passphrase: String?,
        onChunk: (String) -> Unit,
    ): String = ServiceOperations(runner, deployment, service, language)
        .restore(archivePath, passphrase, onChunk)
}

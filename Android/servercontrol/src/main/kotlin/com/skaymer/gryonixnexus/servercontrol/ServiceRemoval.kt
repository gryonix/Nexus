package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ManagedService

enum class RemovalScope {
    /** One service, through the uninstall wrapper's per-service arm */
    SERVICE,

    EVERYTHING,
}

/** Which implementation a removal goes through */
object ServiceRemovalRouting {
    fun route(
        scope: RemovalScope,
        usesAgent: Boolean,
        agentTransportAvailable: Boolean,
    ): ServiceControlRoute {
        if (scope != RemovalScope.SERVICE) return ServiceControlRoute.SSH
        return ServiceControlRouting.route(usesAgent, agentTransportAvailable)
    }
}

interface ServiceRemovalManaging {
    suspend fun remove(
        service: ManagedService,
        purge: PurgeOptions,
        onChunk: (String) -> Unit = {},
    ): String
}

class SSHServiceRemoval(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
    private val language: AppLanguage = AppLanguage.EN,
) : ServiceRemovalManaging {
    override suspend fun remove(
        service: ManagedService,
        purge: PurgeOptions,
        onChunk: (String) -> Unit,
    ): String = ServiceOperations(runner, deployment, service, language)
        .uninstall(purge, onChunk)
}

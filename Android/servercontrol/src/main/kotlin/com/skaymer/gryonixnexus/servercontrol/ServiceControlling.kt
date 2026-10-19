package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ManagedService

enum class ServicePowerAction(val rawValue: String) {
    START("start"),
    STOP("stop"),
    RESTART("restart"),
}

interface ServiceControlling {
    suspend fun status(service: ManagedService): List<ContainerStatus>

    suspend fun power(
        action: ServicePowerAction,
        service: ManagedService,
        onProgress: (String) -> Unit = {},
    ): List<ContainerStatus>
}

/** Which implementation a deployment's management goes through */
enum class ServiceControlRoute(val rawValue: String) {
    SSH("ssh"),
    AGENT("agent"),
}

object ServiceControlRouting {
    fun route(usesAgent: Boolean, agentTransportAvailable: Boolean): ServiceControlRoute =
        if (usesAgent && agentTransportAvailable) ServiceControlRoute.AGENT else ServiceControlRoute.SSH
}

/** The SSH implementation: the existing catalog-derived commands, unchanged */
class SSHServiceControl(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
    private val language: AppLanguage = AppLanguage.EN,
) : ServiceControlling {
    private fun operations(service: ManagedService): ServiceOperations =
        ServiceOperations(runner, deployment, service, language)

    override suspend fun status(service: ManagedService): List<ContainerStatus> =
        operations(service).status()

    override suspend fun power(
        action: ServicePowerAction,
        service: ManagedService,
        onProgress: (String) -> Unit,
    ): List<ContainerStatus> {
        val operations = operations(service)
        when (action) {
            ServicePowerAction.START -> operations.start()
            ServicePowerAction.STOP -> operations.stop()
            ServicePowerAction.RESTART -> operations.restart()
        }
        return operations.status()
    }
}

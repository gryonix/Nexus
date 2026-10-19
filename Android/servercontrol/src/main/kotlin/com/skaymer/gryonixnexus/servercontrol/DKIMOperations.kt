package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import kotlin.time.Duration.Companion.seconds

interface DKIMManaging {
    suspend fun fetchRecords(): List<DKIMRecord>
}

/** Which implementation a deployment's DKIM re-read goes through */
object DKIMRouting {
    fun route(
        usesAgent: Boolean,
        agentTransportAvailable: Boolean,
        hasMailEngine: Boolean,
    ): ServiceControlRoute {
        if (!hasMailEngine) return ServiceControlRoute.SSH
        return ServiceControlRouting.route(usesAgent, agentTransportAvailable)
    }
}

/** The SSH implementation: the existing mailcow-only dump command, unchanged */
class SSHDKIMOperations(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
) : DKIMManaging {
    override suspend fun fetchRecords(): List<DKIMRecord> {
        val command = CommandCatalog.Mailcow.DKIM_DUMP
        val host = ServiceRegistry.mailEngine(deployment.services)
            ?.let { deployment.hostRunning(it) }
            ?: deployment.servicesHost
        val result = runner.run(command, host, 60.seconds)
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(command, result.exitCode, result.stderr)
        }
        return DKIMRecordParser.parse(result.stdout)
    }
}

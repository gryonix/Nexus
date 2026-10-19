package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.SetServiceUpstreamRequest

/** One machine of a deployment, driven through its own agent */
class AgentServiceMoveMachine(
    private val client: AgentClient,
    private val shell: ServiceMoveShell? = null,
) : ServiceMoveMachine {
    override suspend fun hasService(service: ServiceID): Boolean =
        client.serviceStatus(agentID(service)).installed

    override suspend fun estimatedBytes(service: ServiceID): Long =
        AgentBackupOperations(client).estimate(managed(service))?.dataBytes ?: 0L

    override suspend fun install(service: ServiceID, context: AgentInstallContext, log: (String) -> Unit) {
        AgentInstallOperations(client).install(service, context, onChunk = log)
    }

    override suspend fun backUp(service: ServiceID, log: (String) -> Unit): ServiceMoveArchive {
        val id = agentID(service)
        val outcome = AgentBackupOperations(client).backup(managed(service), false, null, log)
        val listing = client.listBackups(id).archives
        val found = outcome.path?.let { path -> listing.firstOrNull { it.path == path } } ?: listing.firstOrNull()
        if (found == null || found.directory) throw ServiceMoveProblem.NoArchive
        return ServiceMoveArchive(found.path, found.name, found.size_bytes)
    }

    override suspend fun start(service: ServiceID, log: (String) -> Unit) {
        AgentCommandRunner(client).power(ServicePowerAction.START, managed(service), log)
    }

    override suspend fun stop(service: ServiceID, log: (String) -> Unit) {
        AgentCommandRunner(client).power(ServicePowerAction.STOP, managed(service), log)
    }

    override suspend fun restore(service: ServiceID, archivePath: String, log: (String) -> Unit) {
        AgentRestoreOperations(client).restore(managed(service), archivePath, null, log)
    }

    override suspend fun removeCopy(service: ServiceID, log: (String) -> Unit) {
        if (!hasService(service)) return
        AgentServiceRemoval(client).remove(managed(service), PurgeOptions(data = true, backups = false), log)
    }

    override suspend fun deleteBackup(service: ServiceID, path: String) {
        client.deleteBackup(agentID(service), path)
    }

    override suspend fun prepareSend(transferID: String): String = client.prepareMoveSend(transferID)

    override suspend fun prepareReceive(
        transferID: String,
        service: ServiceID,
        publicKey: String,
        expectedBytes: Long,
    ): ServiceMoveGrant {
        val user = shell?.loginUser ?: throw ServiceMoveProblem.NoLoginAccess
        val grant = client.prepareMoveReceive(transferID, agentID(service), user, publicKey, expectedBytes)
        return ServiceMoveGrant(grant.authorized_key_line, grant.host_keys, grant.free_bytes)
    }

    override suspend fun authorize(grant: ServiceMoveGrant) {
        shell?.appendAuthorizedKey(grant.authorizedKeyLine)
    }

    override suspend fun revoke(transferID: String) {
        shell?.removeAuthorizedKeys(marker(transferID))
    }

    override suspend fun send(
        transferID: String,
        service: ServiceID,
        archivePath: String,
        target: ServiceMoveEndpoint,
        hostKeys: String,
        log: (String) -> Unit,
    ): ServiceMoveSent {
        var sent: ServiceMoveSent? = null
        client.sendMoveData(transferID, agentID(service), archivePath, target.host, target.port, target.user, hostKeys)
            .collect { event ->
                when (event.phase) {
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS -> log(lineOf(event.text))
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED ->
                        sent = ServiceMoveSent(event.bytes, event.sha256, event.archive_name)
                    else -> Unit
                }
            }
        return sent ?: throw ServiceMoveProblem.NoArchive
    }

    override suspend fun accept(
        transferID: String,
        service: ServiceID,
        sent: ServiceMoveSent,
        log: (String) -> Unit,
    ): String {
        var path: String? = null
        client.acceptMoveData(transferID, agentID(service), sent.sha256, sent.bytes, sent.archiveName)
            .collect { event ->
                when (event.phase) {
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS -> log(lineOf(event.text))
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED -> path = event.archive_path
                    else -> Unit
                }
            }
        return path?.takeIf { it.isNotEmpty() } ?: throw ServiceMoveProblem.NoArchive
    }

    override suspend fun discard(transferID: String) {
        client.discardMoveTransfer(transferID)
    }

    override suspend fun site(change: ServiceMoveSiteChange): ServiceMoveSite {
        val state = client.setServiceUpstream(
            SetServiceUpstreamRequest(
                service_id = agentID(change.service),
                local_port = change.localPort,
                local_https = change.localHTTPS,
                overwrite_forwarded_for = change.overwriteForwardedFor,
                remote_address = change.remoteAddress.orEmpty(),
                dry_run = change.dryRun,
            ),
        )
        return when (state.current) {
            "local" -> ServiceMoveSite.Local
            "remote" -> ServiceMoveSite.Remote(state.remote_address)
            "missing" -> ServiceMoveSite.Missing
            else -> ServiceMoveSite.Unknown
        }
    }

    override suspend fun probe(service: ServiceID): ServiceMoveProbe {
        val answer = client.probeServiceUpstream(agentID(service))
        return ServiceMoveProbe(answer.answered, answer.unavailable, answer.status, answer.detail)
    }

    private fun lineOf(text: String): String = if (text.endsWith("\n")) text else text + "\n"

    private fun agentID(service: ServiceID): String =
        AgentServiceMapping.agentID(service) ?: throw AgentControlError.UnsupportedService(service.rawValue)

    private fun managed(service: ServiceID): ManagedService =
        ServiceRegistry.service(service) ?: throw AgentControlError.UnsupportedService(service.rawValue)

    companion object {
        fun marker(transferID: String): String = "gryonixnexus-move-$transferID"
    }
}

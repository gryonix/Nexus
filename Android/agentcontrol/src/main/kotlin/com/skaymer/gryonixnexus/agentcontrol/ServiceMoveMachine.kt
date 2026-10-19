package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceID

data class ServiceMoveArchive(val path: String, val name: String, val bytes: Long)

data class ServiceMoveGrant(val authorizedKeyLine: String, val hostKeys: String, val freeBytes: Long)

data class ServiceMoveSent(val bytes: Long, val sha256: String, val archiveName: String)

/** How the front proxies one service */
sealed class ServiceMoveSite {
    data object Local : ServiceMoveSite()
    data class Remote(val address: String) : ServiceMoveSite()
    data object Missing : ServiceMoveSite()
    data object Unknown : ServiceMoveSite()
}

data class ServiceMoveSiteChange(
    val service: ServiceID,
    val localPort: Int,
    val localHTTPS: Boolean,
    val overwriteForwardedFor: Boolean,
    /** Null serves the site from the front itself */
    val remoteAddress: String?,
    val dryRun: Boolean = false,
)

data class ServiceMoveProbe(val answered: Boolean, val unavailable: Boolean, val status: Int, val detail: String)

/** Where the old machine dials the new one */
data class ServiceMoveEndpoint(val host: String, val port: Int, val user: String)

interface ServiceMoveShell {
    val loginUser: String
    suspend fun appendAuthorizedKey(line: String)
    suspend fun removeAuthorizedKeys(containing: String)
}

interface ServiceMoveMachine {
    suspend fun hasService(service: ServiceID): Boolean
    suspend fun estimatedBytes(service: ServiceID): Long
    suspend fun install(service: ServiceID, context: AgentInstallContext, log: (String) -> Unit)
    suspend fun backUp(service: ServiceID, log: (String) -> Unit): ServiceMoveArchive
    suspend fun start(service: ServiceID, log: (String) -> Unit)
    suspend fun stop(service: ServiceID, log: (String) -> Unit)
    suspend fun restore(service: ServiceID, archivePath: String, log: (String) -> Unit)
    suspend fun removeCopy(service: ServiceID, log: (String) -> Unit)
    suspend fun deleteBackup(service: ServiceID, path: String)

    suspend fun prepareSend(transferID: String): String
    suspend fun prepareReceive(transferID: String, service: ServiceID, publicKey: String, expectedBytes: Long): ServiceMoveGrant
    suspend fun authorize(grant: ServiceMoveGrant)
    suspend fun revoke(transferID: String)
    suspend fun send(
        transferID: String,
        service: ServiceID,
        archivePath: String,
        target: ServiceMoveEndpoint,
        hostKeys: String,
        log: (String) -> Unit,
    ): ServiceMoveSent
    suspend fun accept(transferID: String, service: ServiceID, sent: ServiceMoveSent, log: (String) -> Unit): String
    suspend fun discard(transferID: String)

    suspend fun site(change: ServiceMoveSiteChange): ServiceMoveSite
    suspend fun probe(service: ServiceID): ServiceMoveProbe
}

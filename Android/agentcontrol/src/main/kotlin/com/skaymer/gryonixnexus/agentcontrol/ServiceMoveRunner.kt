package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveRecord
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveStep
import kotlinx.coroutines.CancellationException

data class ServiceMovePlan(
    val service: ServiceID,
    val target: ServiceMoveEndpoint,
    val sourceEntryAddress: String?,
    val targetEntryAddress: String?,
    val localPort: Int,
    val localHTTPS: Boolean,
    val overwriteForwardedFor: Boolean,
    val installContext: AgentInstallContext,
)

sealed class ServiceMoveProblem : Exception() {
    data object NotOnSource : ServiceMoveProblem()
    data object AlreadyOnTarget : ServiceMoveProblem()
    data object NoSiteOnFront : ServiceMoveProblem()
    data class FrontDisagrees(val found: String) : ServiceMoveProblem()
    data class NotAnswering(val status: Int, val detail: String) : ServiceMoveProblem()
    data object NoArchive : ServiceMoveProblem()
    data object NoLoginAccess : ServiceMoveProblem()
}

sealed class ServiceMoveEvent {
    data class Step(val step: ServiceMoveStep) : ServiceMoveEvent()
    data class Log(val text: String) : ServiceMoveEvent()
    data object Undoing : ServiceMoveEvent()
}

/** What undoing a failed move managed to do */
data class ServiceMoveUndo(
    val entryRestored: Boolean = false,
    val sourceStarted: Boolean = false,
    val targetCopyRemoved: Boolean = false,
    val problems: List<String> = emptyList(),
)

class ServiceMoveFailure(val step: ServiceMoveStep, val underlying: Throwable, val undone: ServiceMoveUndo) :
    Exception(underlying.message, underlying)

class ServiceMoveRunner(
    private val plan: ServiceMovePlan,
    private var record: ServiceMoveRecord,
    private val source: ServiceMoveMachine,
    private val target: ServiceMoveMachine,
    private val front: ServiceMoveMachine,
    private val onRecord: (ServiceMoveRecord) -> Unit,
    private val onEvent: (ServiceMoveEvent) -> Unit,
) {
    private val problems = mutableListOf<String>()
    private val log: (String) -> Unit = { onEvent(ServiceMoveEvent.Log(it)) }

    suspend fun run() {
        val stages: List<Pair<ServiceMoveStep, suspend () -> Unit>> = listOf(
            ServiceMoveStep.CHECK to ::check, ServiceMoveStep.INSTALL to ::install,
            ServiceMoveStep.BACKUP to ::backUp, ServiceMoveStep.STOP to ::stop,
            ServiceMoveStep.SEND to ::send, ServiceMoveStep.RESTORE to ::restore,
            ServiceMoveStep.SWITCH_ENTRY to ::switchEntry, ServiceMoveStep.VERIFY to ::verify,
            ServiceMoveStep.FINISH to ::finish,
        )
        for ((step, work) in stages) {
            if (step < record.step) continue
            enter(step)
            try {
                work()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                throw ServiceMoveFailure(step, error, undo())
            }
        }
    }

    suspend fun undo(): ServiceMoveUndo {
        onEvent(ServiceMoveEvent.Undoing)
        var entry = false
        var started = false
        var removed = false
        if (record.switchedEntry) {
            entry = attempt("pointing the site back") { front.site(siteChange(plan.sourceEntryAddress)) }
        }
        if (record.sourceStopped) {
            started = attempt("starting the old copy") { source.start(plan.service, log) }
        }
        if (record.installedOnTarget) {
            removed = attempt("removing the new copy") { target.removeCopy(plan.service, log) }
        }
        cleanUpTransfer()
        return ServiceMoveUndo(entry, started, removed, problems.toList())
    }

    private fun enter(step: ServiceMoveStep) {
        record = record.copy(step = step)
        onRecord(record)
        onEvent(ServiceMoveEvent.Step(step))
    }

    private fun save(change: (ServiceMoveRecord) -> ServiceMoveRecord) {
        record = change(record)
        onRecord(record)
    }

    private suspend fun attempt(what: String, body: suspend () -> Unit): Boolean = try {
        body()
        true
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        problems += "$what: ${error.message ?: error.toString()}"
        false
    }

    private fun siteChange(remote: String?, dryRun: Boolean = false) = ServiceMoveSiteChange(
        plan.service, plan.localPort, plan.localHTTPS, plan.overwriteForwardedFor, remote, dryRun,
    )

    // -------------------------------------------------------------- Stages

    private suspend fun check() {
        if (!source.hasService(plan.service)) throw ServiceMoveProblem.NotOnSource
        if (target.hasService(plan.service)) throw ServiceMoveProblem.AlreadyOnTarget
        val expected = plan.sourceEntryAddress?.let { ServiceMoveSite.Remote(it) } ?: ServiceMoveSite.Local
        val found = front.site(siteChange(plan.sourceEntryAddress, dryRun = true))
        if (found == ServiceMoveSite.Missing) throw ServiceMoveProblem.NoSiteOnFront
        if (found != expected) throw ServiceMoveProblem.FrontDisagrees(words(found))
        onEvent(ServiceMoveEvent.Log("about ${source.estimatedBytes(plan.service)} bytes of data"))
    }

    private suspend fun install() {
        save { it.copy(installedOnTarget = true) }
        target.install(plan.service, plan.installContext, log)
    }

    private suspend fun backUp() {
        val archive = source.backUp(plan.service, log)
        save { it.copy(archivePath = archive.path, archiveName = archive.name, archiveBytes = archive.bytes) }
    }

    private suspend fun stop() {
        save { it.copy(sourceStopped = true) }
        source.stop(plan.service, log)
    }

    private suspend fun send() {
        val path = record.archivePath ?: throw ServiceMoveProblem.NoArchive
        val id = record.transferID
        val key = source.prepareSend(id)
        val grant = target.prepareReceive(id, plan.service, key, record.archiveBytes ?: 0L)
        target.authorize(grant)
        try {
            val sent = source.send(id, plan.service, path, plan.target, grant.hostKeys, log)
            save { it.copy(sha256 = sent.sha256, sentBytes = sent.bytes, archiveName = sent.archiveName) }
        } finally {
            runCatching { target.revoke(id) }
        }
    }

    private suspend fun restore() {
        val name = record.archiveName
        val sha = record.sha256
        val bytes = record.sentBytes
        if (name == null || sha == null || bytes == null) throw ServiceMoveProblem.NoArchive
        val path = target.accept(record.transferID, plan.service, ServiceMoveSent(bytes, sha, name), log)
        save { it.copy(targetArchivePath = path) }
        target.restore(plan.service, path, log)
    }

    private suspend fun switchEntry() {
        save { it.copy(switchedEntry = true) }
        front.site(siteChange(plan.targetEntryAddress))
    }

    private suspend fun verify() {
        val answer = front.probe(plan.service)
        if (answer.unavailable) {
            onEvent(ServiceMoveEvent.Log("could not check the site: ${answer.detail}"))
        } else if (!answer.answered) {
            throw ServiceMoveProblem.NotAnswering(answer.status, answer.detail)
        }
    }

    private suspend fun finish() {
        cleanUpTransfer()
        record.targetArchivePath?.let { runCatching { target.deleteBackup(plan.service, it) } }
    }

    private suspend fun cleanUpTransfer() {
        val id = record.transferID
        runCatching { target.revoke(id) }
        runCatching { source.discard(id) }
        runCatching { target.discard(id) }
    }

    private fun words(site: ServiceMoveSite): String = when (site) {
        ServiceMoveSite.Local -> "local"
        is ServiceMoveSite.Remote -> site.address
        ServiceMoveSite.Missing -> "missing"
        ServiceMoveSite.Unknown -> "unknown"
    }
}

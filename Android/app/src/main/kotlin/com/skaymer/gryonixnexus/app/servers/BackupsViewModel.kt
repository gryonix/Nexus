package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentcontrol.PreRestoreCopy
import com.skaymer.gryonixnexus.agentcontrol.PreRestoreManaging
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.ANSIStripper
import com.skaymer.gryonixnexus.servercontrol.AutoBackupSettings
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.servercontrol.AccessGrantCommand
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDriveSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDrivesState
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationState
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationTestResult
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.BackupEstimate
import com.skaymer.gryonixnexus.servercontrol.BackupNowChoice
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.ServiceOperations
import com.skaymer.gryonixnexus.servercontrol.ServiceBackupManaging
import com.skaymer.gryonixnexus.servercontrol.ServiceRestoreManaging
import com.skaymer.gryonixnexus.agentcontrol.AgentBackupOperations
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.BackupOverview
import com.skaymer.gryonixnexus.servercontrol.FleetBackup
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What one service's backup list looks like on screen */
data class Transfer(val fileName: String, val isSending: Boolean)

data class ServiceBackupsState(
    val entries: List<BackupEntry> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val transfer: Transfer? = null,
    /** Whether the server has answered about this service at all */
    val hasAnswered: Boolean = false,
) {
    val saysThereAreNone: Boolean
        get() = hasAnswered && errorMessage == null && entries.isEmpty()
}

data class BackupEstimateState(
    val service: ServiceID,
    val isLoading: Boolean = true,
    val estimate: BackupEstimate? = null,
    val errorMessage: String? = null,
)

/** One backup or restore in flight, and how it ended */
data class BackupRun(
    val service: ServiceID,
    val kind: Kind,
    val log: String = "",
    val isFinished: Boolean = false,
    /** Size of the finished archive, when the wrapper named one */
    val sizeBytes: Long? = null,
    val errorMessage: String? = null,
) {
    enum class Kind { BACKUP, RESTORE }
}

/** Everything the backups card draws about one server */
data class BackupsState(
    val services: Map<ServiceID, ServiceBackupsState> = emptyMap(),
    /** Old restore copies, per service */
    val oldCopies: Map<ServiceID, List<PreRestoreCopy>> = emptyMap(),
    val estimate: BackupEstimateState? = null,
    val schedule: AutoBackupSettings = AutoBackupSettings(),
    /** Whether the SERVER has answered about its schedule */
    val hasLoadedSchedule: Boolean = false,
    val isSaving: Boolean = false,
    val scheduleError: String? = null,
    val run: BackupRun? = null,
    val destination: BackupDestinationState = BackupDestinationState(),
    val hasLoadedDestination: Boolean = false,
    val destinationBusy: Boolean = false,
    val destinationError: String? = null,
    val destinationCheck: BackupDestinationTestResult? = null,
    val destinationKeyAuthorizedOn: String? = null,
)

/** Backups of one server and its drives */
data class AllBackupsState(
    val rows: List<FleetBackup> = emptyList(),
    /** Why this server did not list its backups */
    val failure: String? = null,
    /** Why the last delete did not go through */
    val actionError: String? = null,
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
)

class BackupsViewModel(
    private val scope: CoroutineScope,
    /** How backups are performed for one service */
    private val backups: suspend (Deployment, ManagedService) -> ServiceBackupManaging,
    private val restores: suspend (Deployment, ManagedService) -> ServiceRestoreManaging,
    private val schedules: suspend (Deployment) -> BackupScheduleManaging,
    private val browsers: suspend (Deployment) -> RemoteFileBrowser,
    /** The plain command runner, for the upload's own staging step */
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (Deployment) -> Unit = {},
    /** Old restore copies, when the agent reports them */
    private val oldCopies: suspend (Deployment, ManagedService) -> PreRestoreManaging? = { _, _ -> null },
) {
    private val _state = MutableStateFlow(BackupsState())
    val state: StateFlow<BackupsState> = _state.asStateFlow()

    private val _all = MutableStateFlow(AllBackupsState())
    val all: StateFlow<AllBackupsState> = _all.asStateFlow()

    /** One server's answer, with a reason if it failed */
    private data class ServerAnswer(val rows: List<FleetBackup>, val failed: Boolean, val reason: String? = null)

    /** Deletes each backup, then reads the list again */
    fun deleteMany(deployment: Deployment, rows: List<Pair<ServiceID, BackupEntry>>) {
        scope.launch {
            var failure: String? = null
            for ((id, entry) in rows) {
                val service = ServiceRegistry.service(id) ?: continue
                val path = path(service, deployment.serviceContext, entry) ?: continue
                try {
                    backups(deployment, service).deleteBackup(service, path)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failed: Exception) {
                    release(deployment)
                    failure = failure ?: reason(failed)
                }
            }
            _all.update { it.copy(actionError = failure, isLoading = false) }
            loadAll(deployment)
        }
    }

    /** Loads every backup of the server, newest first */
    fun loadAll(deployment: Deployment) {
        if (_all.value.isLoading) return
        _all.value = AllBackupsState(isLoading = true, actionError = _all.value.actionError)
        scope.launch {
            val answer = withTimeoutOrNull(ALL_DEADLINE_MILLIS) {
                listEverything(deployment) { rows ->
                    _all.update { it.copy(rows = BackupOverview.sorted(rows)) }
                }
            } ?: ServerAnswer(_all.value.rows, true, OperationNotices.text(R.string.backups_no_answer))
            _all.value = AllBackupsState(
                rows = BackupOverview.sorted(answer.rows),
                failure = if (answer.failed) answer.reason else null,
                actionError = _all.value.actionError,
                isLoading = false,
                hasLoaded = true,
            )
        }
    }

    /** One agent call if possible, then per service */
    private suspend fun listEverything(
        deployment: Deployment,
        progress: (List<FleetBackup>) -> Unit,
    ): ServerAnswer {
        val rows = mutableListOf<FleetBackup>()
        var failed = false
        var reason: String? = null
        val remaining = backupCapableServices(deployment).toMutableList()
        val seams = remaining.associateWith { backups(deployment, it) }
        val agent = seams.values.filterIsInstance<AgentBackupOperations>().firstOrNull()
        if (agent != null) {
            val all = runCatching { agent.listAll() }.getOrNull()
            if (all != null) {
                val covered = mutableSetOf<String>()
                remaining.removeAll { service ->
                    val id = AgentServiceMapping.agentID(service.id)
                    val entries = id?.let { all[it] } ?: return@removeAll false
                    if (covered.add(id)) {
                        rows += entries.map { FleetBackup(deployment.id, deployment.name, service.id.rawValue, service.displayName, it) }
                    }
                    true
                }
                progress(rows.toList())
            }
        }
        for (service in remaining) {
            try {
                seams.getValue(service).listBackups(service).forEach {
                    rows += FleetBackup(deployment.id, deployment.name, service.id.rawValue, service.displayName, it)
                }
                progress(rows.toList())
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                failed = true
                reason = reason ?: reason(failure)
            }
        }
        return ServerAnswer(rows, failed, reason)
    }

    /** What is in one service's backup directory, newest first */
    fun list(deployment: Deployment, id: ServiceID) {
        val service = ServiceRegistry.service(id) ?: return
        scope.launch {
            update(id) { it.copy(isLoading = true, errorMessage = null) }
            try {
                val entries = backups(deployment, service).listBackups(service)
                update(id) {
                    ServiceBackupsState(entries = entries, isLoading = false, hasAnswered = true)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                update(id) {
                    ServiceBackupsState(
                        entries = emptyList(),
                        isLoading = false,
                        errorMessage = reason(failure),
                        hasAnswered = true,
                    )
                }
            }
            loadOldCopies(deployment, service)
        }
    }

    /** Deletes one old copy a restore left behind */
    fun deleteOldCopy(deployment: Deployment, id: ServiceID, copy: PreRestoreCopy) {
        val service = ServiceRegistry.service(id) ?: return
        scope.launch {
            try {
                val left = oldCopies(deployment, service)?.delete(copy) ?: return@launch
                setOldCopies(id, left)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                update(id) { it.copy(errorMessage = reason(failure)) }
            }
        }
    }

    private suspend fun loadOldCopies(deployment: Deployment, service: ManagedService) {
        try {
            setOldCopies(service.id, oldCopies(deployment, service)?.copies(service).orEmpty())
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            setOldCopies(service.id, emptyList())
        }
    }

    private fun setOldCopies(id: ServiceID, copies: List<PreRestoreCopy>) {
        _state.value = _state.value.copy(oldCopies = _state.value.oldCopies + (id to copies))
    }

    fun estimate(deployment: Deployment, id: ServiceID) {
        val service = ServiceRegistry.service(id) ?: return
        _state.value = _state.value.copy(estimate = BackupEstimateState(service = id))
        scope.launch {
            try {
                val estimate = backups(deployment, service).estimate(service)
                setEstimate(id) { it.copy(isLoading = false, estimate = estimate) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                setEstimate(id) { it.copy(isLoading = false, errorMessage = reason(failure)) }
            }
        }
    }

    fun clearEstimate() {
        _state.value = _state.value.copy(estimate = null)
    }

    /** Runs one backup and re-lists afterwards */
    fun backUp(
        deployment: Deployment,
        id: ServiceID,
        encrypt: Boolean?,
        passphrase: String?,
    ) {
        scope.launch { runBackup(deployment, id, encrypt, passphrase) }
    }

    /** Backs up each chosen service in turn */
    fun backUpMany(deployment: Deployment, choice: BackupNowChoice) {
        val chosen = choice.services.mapNotNull { id -> ServiceRegistry.service(ServiceID(id)) }
        val defaultsOn = encryptedByDefault(deployment, chosen)
        val always = alwaysEncrypted(deployment, chosen)
        scope.launch {
            chosen.forEach { service ->
                val encrypt = choice.encrypts(service.id.rawValue, defaultsOn, always)
                runBackup(deployment, service.id, encrypt, choice.passphraseToSend)
            }
        }
    }

    /** One service's size, or null when unknown */
    suspend fun estimateOf(deployment: Deployment, service: ManagedService): BackupEstimate? = try {
        backups(deployment, service).estimate(service)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        null
    }

    /** Whether the server holds a backup key; null when unknown */
    suspend fun hasStoredKey(deployment: Deployment): Boolean? {
        if (DemoDeployments.isDemoID(deployment.id)) return true
        return try {
            schedules(deployment).loadDrives().takeIf { it.supported }?.hasPassphrase
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            null
        }
    }

    private suspend fun runBackup(deployment: Deployment, id: ServiceID, encrypt: Boolean?, passphrase: String?) {
        val service = ServiceRegistry.service(id) ?: return
        _state.value = _state.value.copy(
            run = BackupRun(service = id, kind = BackupRun.Kind.BACKUP),
        )
        runNotice = OperationNotices.start(
            R.string.backups_running, service.displayName, server = deployment.name, kind = OperationKind.BACKUP,
        )
        runNotice?.stopsAgentJobs(deployment)
        try {
            val outcome = backups(deployment, service)
                .backup(service, encrypt, passphrase) { chunk -> append(chunk) }
            finish { it.copy(isFinished = true, sizeBytes = outcome.sizeBytes) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            finish { it.copy(isFinished = true, errorMessage = reason(failure)) }
        }
        finishNotice()
        listNow(deployment, service)
    }

    /** Puts one archive back */
    fun restore(
        deployment: Deployment,
        id: ServiceID,
        archivePath: String,
        passphrase: String?,
    ) {
        val service = ServiceRegistry.service(id) ?: return
        scope.launch {
            _state.value = _state.value.copy(
                run = BackupRun(service = id, kind = BackupRun.Kind.RESTORE),
            )
            runNotice = OperationNotices.start(
                R.string.notice_restoring, service.displayName, server = deployment.name, kind = OperationKind.RESTORE,
            )
            runNotice?.stopsAgentJobs(deployment)
            try {
                restores(deployment, service).restore(service, archivePath, passphrase) { chunk ->
                    append(chunk)
                }
                finish { it.copy(isFinished = true) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                finish { it.copy(isFinished = true, errorMessage = reason(failure)) }
            }
            finishNotice()
        }
    }

    fun download(
        deployment: Deployment,
        id: ServiceID,
        entry: BackupEntry,
        onReady: (ByteArray, String) -> Unit,
    ) {
        val service = ServiceRegistry.service(id) ?: return
        val remote = path(service, deployment.serviceContext, entry) ?: return
        scope.launch {
            update(id) { it.copy(transfer = Transfer(entry.name, isSending = false)) }
            try {
                val browser = browsers(deployment)
                val bytes = browser.downloadFile(
                    remote, deployment.hostRunning(id), ServiceOperations.UPLOAD_LIMIT_BYTES,
                )
                update(id) { it.copy(transfer = null) }
                onReady(bytes, entry.name)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                update(id) { it.copy(transfer = null, errorMessage = reason(failure)) }
            }
        }
    }

    fun restoreFromDevice(
        deployment: Deployment,
        id: ServiceID,
        data: ByteArray,
        fileName: String,
        passphrase: String?,
    ) {
        val service = ServiceRegistry.service(id) ?: return
        scope.launch {
            update(id) { it.copy(transfer = Transfer(fileName, isSending = true)) }
            val path = try {
                val browser = browsers(deployment)
                ServiceOperations(runners(deployment), deployment, service)
                    .uploadBackup(data, fileName, browser)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                update(id) { it.copy(transfer = null, errorMessage = reason(failure)) }
                return@launch
            }
            update(id) { it.copy(transfer = null) }
            restore(deployment, id, path, passphrase)
        }
    }

    /** Here, or through this device to another server */
    fun restoreListed(from: Deployment, to: Deployment, row: FleetBackup, passphrase: String?) {
        val id = ServiceID(row.serviceId)
        val service = ServiceRegistry.service(id) ?: return
        val remote = path(service, from.serviceContext, row.entry) ?: return
        if (to.id == from.id) {
            restore(from, id, remote, passphrase)
            return
        }
        scope.launch {
            _all.update { it.copy(actionError = null) }
            val size = row.entry.sizeBytes
            if (size != null && size > COPY_LIMIT_BYTES) {
                _all.update {
                    it.copy(actionError = OperationNotices.text(
                        R.string.backups_restore_too_large, MetricsFormat.bytes(size), MetricsFormat.bytes(COPY_LIMIT_BYTES),
                    ))
                }
                return@launch
            }
            val bytes = try {
                browsers(from).downloadFile(remote, from.hostRunning(id), COPY_LIMIT_BYTES)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                _all.update { it.copy(actionError = reason(failure)) }
                return@launch
            }
            restoreFromDevice(to, id, bytes, row.entry.displayName, passphrase)
        }
    }

    fun delete(deployment: Deployment, id: ServiceID, entry: BackupEntry) {
        val service = ServiceRegistry.service(id) ?: return
        val path = path(service, deployment.serviceContext, entry) ?: return
        scope.launch {
            update(id) { it.copy(isLoading = true, errorMessage = null) }
            try {
                backups(deployment, service).deleteBackup(service, path)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                update(id) { it.copy(isLoading = false, errorMessage = reason(failure)) }
            }
            listNow(deployment, service)
        }
    }

    /** Dismisses a finished run's log */
    fun clearRun() {
        _state.value = _state.value.copy(run = null)
    }

    /** Reads the schedule the machine is holding */
    fun loadSchedule(deployment: Deployment) {
        scope.launch {
            try {
                val settings = schedules(deployment).load()
                _state.value = _state.value.copy(
                    schedule = settings,
                    hasLoadedSchedule = true,
                    scheduleError = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(scheduleError = reason(failure))
            }
        }
    }

    /** Writes a schedule */
    fun saveSchedule(
        deployment: Deployment,
        settings: AutoBackupSettings,
        passphrase: String?,
    ) {
        scope.launch {
            _state.value = _state.value.copy(isSaving = true)
            try {
                schedules(deployment).save(settings, passphrase)
                _state.value = _state.value.copy(
                    schedule = settings,
                    hasLoadedSchedule = true,
                    isSaving = false,
                    scheduleError = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(isSaving = false, scheduleError = reason(failure))
            }
        }
    }

    // ── Destination ──────────────────────────────────────────────────────

    fun loadDestination(deployment: Deployment) {
        scope.launch {
            try {
                val state = schedules(deployment).loadDestination()
                _state.value = _state.value.copy(
                    destination = state,
                    hasLoadedDestination = true,
                    destinationError = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(destinationError = reason(failure))
            }
        }
    }

    fun saveDestination(
        deployment: Deployment,
        settings: BackupDestinationSettings,
        secret: String?,
    ) {
        scope.launch {
            _state.value = _state.value.copy(destinationBusy = true, destinationCheck = null)
            try {
                val seam = schedules(deployment)
                seam.saveDestination(settings, secret)
                _state.value = _state.value.copy(
                    destination = seam.loadDestination(),
                    hasLoadedDestination = true,
                    destinationBusy = false,
                    destinationError = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(
                    destinationBusy = false,
                    destinationError = reason(failure),
                )
            }
        }
    }

    /** Sends one small file and keeps what came back */
    fun checkDestination(deployment: Deployment) {
        scope.launch {
            _state.value = _state.value.copy(destinationBusy = true)
            try {
                val seam = schedules(deployment)
                val result = seam.testDestination()
                _state.value = _state.value.copy(
                    destinationCheck = result,
                    destination = seam.loadDestination(),
                    destinationBusy = false,
                    destinationError = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(
                    destinationBusy = false,
                    destinationCheck = null,
                    destinationError = reason(failure),
                )
            }
        }
    }

    /** USB drives for one server, with their own state */
    fun drives(): BackupDrivesModel = BackupDrivesModel(scope, schedules)

    fun authorizeKey(target: Deployment, publicKey: String) {
        if (publicKey.isEmpty()) return
        scope.launch {
            _state.value = _state.value.copy(destinationBusy = true)
            try {
                val result = runners(target).run(
                    AccessGrantCommand.command(publicKey),
                    target.servicesHost,
                    target.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
                )
                _state.value = _state.value.copy(
                    destinationBusy = false,
                    destinationError = if (result.succeeded) {
                        null
                    } else {
                        OutputTail.tail(result.stderr)
                    },
                    destinationKeyAuthorizedOn = if (result.succeeded) target.name else null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(target)
                _state.value = _state.value.copy(
                    destinationBusy = false,
                    destinationError = reason(failure),
                )
            }
        }
    }

    fun reset() {
        _state.value = BackupsState()
    }

    private suspend fun listNow(deployment: Deployment, service: ManagedService) {
        try {
            val entries = backups(deployment, service).listBackups(service)
            update(service.id) {
                ServiceBackupsState(entries = entries, isLoading = false, hasAnswered = true)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            update(service.id) {
                ServiceBackupsState(
                    isLoading = false,
                    errorMessage = reason(failure),
                    hasAnswered = true,
                )
            }
        }
    }

    private var runNotice: OperationNotice? = null

    private fun finishNotice() {
        runNotice?.finish(OperationNotices.text(R.string.notice_done), _state.value.run?.errorMessage)
        runNotice = null
    }

    private fun append(chunk: String) {
        runNotice?.update(OperationNotices.lastLine(chunk))
        val run = _state.value.run ?: return
        val log = OutputTail.tail(WrapperLogText.readable(ANSIStripper.strip(run.log + chunk)))
        _state.value = _state.value.copy(run = run.copy(log = log))
    }

    private fun finish(change: (BackupRun) -> BackupRun) {
        val run = _state.value.run ?: return
        _state.value = _state.value.copy(run = change(run))
    }

    private fun update(id: ServiceID, change: (ServiceBackupsState) -> ServiceBackupsState) {
        val current = _state.value.services
        _state.value = _state.value.copy(
            services = current + (id to change(current[id] ?: ServiceBackupsState())),
        )
    }

    private fun setEstimate(
        id: ServiceID,
        change: (BackupEstimateState) -> BackupEstimateState,
    ) {
        val current = _state.value.estimate ?: return
        if (current.service != id) return
        _state.value = _state.value.copy(estimate = change(current))
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        const val ALL_DEADLINE_MILLIS: Long = 20_000
        const val LARGE_BACKUP_BYTES: Long = 10L * 1024 * 1024 * 1024

        fun path(
            service: ManagedService,
            context: ServiceContext,
            entry: BackupEntry,
        ): String? {
            val dir = service.actions(context).backup?.listDirectory ?: return null
            return if (entry.name.startsWith("/")) entry.name else "$dir/${entry.name}"
        }

        fun backupCapableServices(deployment: Deployment): List<ManagedService> =
            deployment.services.mapNotNull { ServiceRegistry.service(it) }
                .filter { it.actions(deployment.serviceContext).backup != null }

        /** Services whose archives are encrypted unless switched off */
        fun encryptedByDefault(deployment: Deployment, services: List<ManagedService>): Set<String> =
            services.filter { it.actions(deployment.serviceContext).backup?.encryptsByDefault == true }
                .map { it.id.rawValue }.toSet()

        /** Services whose archives are always encrypted */
        fun alwaysEncrypted(deployment: Deployment, services: List<ManagedService>): Set<String> =
            services.filter { it.actions(deployment.serviceContext).backup is BackupSpec.EncryptedVolume }
                .map { it.id.rawValue }.toSet()

        /** What passes through the device both ways */
        const val COPY_LIMIT_BYTES: Long = ServiceOperations.UPLOAD_LIMIT_BYTES

        /** Servers running the same service, this one first */
        fun restoreTargets(here: Deployment, row: FleetBackup, fleet: List<Deployment>): List<Deployment> {
            val service = ServiceRegistry.service(ServiceID(row.serviceId)) ?: return emptyList()
            fun takes(server: Deployment) =
                server.services.contains(service.id) && service.actions(server.serviceContext).restore != null
            if (!takes(here)) return emptyList()
            val movable = row.entry.drive == null && !row.entry.isDirectory
            val others = if (movable) fleet.filter { it.id != here.id && takes(it) }.sortedBy { it.name } else emptyList()
            return listOf(here) + others
        }

        fun restorableServices(deployment: Deployment): List<ManagedService> =
            deployment.services.mapNotNull { ServiceRegistry.service(it) }
                .filter { it.actions(deployment.serviceContext).restore != null }

        /** Whether restoring THIS archive needs a passphrase */
        fun restoreNeedsPassphrase(
            service: ManagedService,
            context: ServiceContext,
            archivePath: String,
        ): Boolean =
            service.actions(context).restore?.needsPassphrase(archivePath) ?: false

        fun scheduleNeedsPassphrase(
            deployment: Deployment,
            settings: AutoBackupSettings,
        ): Boolean {
            if (!settings.isOn) return false
            return backupCapableServices(deployment).any {
                settings.services.contains(it.id.rawValue) &&
                    it.actions(deployment.serviceContext).backup is BackupSpec.EncryptedVolume
            }
        }

        /** Whether the server already holds a passphrase for unattended runs */
        fun hasStoredPassphrase(
            deployment: Deployment,
            saved: AutoBackupSettings,
        ): Boolean = scheduleNeedsPassphrase(deployment, saved)

        /** Whether a draft schedule may be written */
        fun canSaveSchedule(
            deployment: Deployment,
            draft: AutoBackupSettings,
            saved: AutoBackupSettings,
            typedPassphrase: String,
            isSaving: Boolean,
        ): Boolean {
            if (isSaving) return false
            if (draft.isOn && draft.services.isEmpty()) return false
            if (scheduleNeedsPassphrase(deployment, draft) &&
                !hasStoredPassphrase(deployment, saved) &&
                typedPassphrase.isEmpty()
            ) {
                return false
            }
            return true
        }

        fun passphraseIsUsable(passphrase: String, confirmation: String): Boolean =
            passphrase.isEmpty() || (passphrase.length >= 8 && passphrase == confirmation)

        fun doesNotFit(estimate: BackupEstimate?): Boolean =
            estimate != null && !estimate.fitsOnDisk

        fun isLarge(estimate: BackupEstimate?): Boolean =
            estimate != null && estimate.dataBytes >= LARGE_BACKUP_BYTES
    }
}

/** Reading and writing the unattended backup schedule */
interface BackupScheduleManaging {
    suspend fun load(): AutoBackupSettings
    suspend fun save(settings: AutoBackupSettings, passphrase: String?)

    /** Where the copies go once they exist — see `BackupDestinationSettings` */
    suspend fun loadDestination(): BackupDestinationState
    suspend fun saveDestination(settings: BackupDestinationSettings, secret: String?)
    suspend fun testDestination(): BackupDestinationTestResult

    /** USB drives that take a copy too */
    suspend fun loadDrives(): BackupDrivesState = BackupDrivesState(supported = false)
    suspend fun saveDrives(settings: BackupDriveSettings) {}
}

class SSHBackupSchedule(
    private val operations: com.skaymer.gryonixnexus.servercontrol.AutoBackupOperations,
) : BackupScheduleManaging {
    override suspend fun load(): AutoBackupSettings = operations.load()

    override suspend fun save(settings: AutoBackupSettings, passphrase: String?) =
        operations.save(settings, passphrase)
    override suspend fun loadDestination(): BackupDestinationState = operations.loadDestination()

    override suspend fun saveDestination(settings: BackupDestinationSettings, secret: String?) =
        operations.saveDestination(settings, secret)

    override suspend fun testDestination(): BackupDestinationTestResult = operations.testDestination()

    override suspend fun loadDrives(): BackupDrivesState = operations.loadDrives()

    override suspend fun saveDrives(settings: BackupDriveSettings) = operations.saveDrives(settings)
}

class AgentBackupSchedule(
    private val operations: com.skaymer.gryonixnexus.agentcontrol.AgentAutoBackupOperations,
) : BackupScheduleManaging {
    override suspend fun load(): AutoBackupSettings = operations.load()

    override suspend fun save(settings: AutoBackupSettings, passphrase: String?) =
        operations.save(settings, passphrase)
    override suspend fun loadDestination(): BackupDestinationState = operations.loadDestination()

    override suspend fun saveDestination(settings: BackupDestinationSettings, secret: String?) =
        operations.saveDestination(settings, secret)

    override suspend fun testDestination(): BackupDestinationTestResult = operations.testDestination()

    override suspend fun loadDrives(): BackupDrivesState = operations.loadDrives()

    override suspend fun saveDrives(settings: BackupDriveSettings) = operations.saveDrives(settings)
}

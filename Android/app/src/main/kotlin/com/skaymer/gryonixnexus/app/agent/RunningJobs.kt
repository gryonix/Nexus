package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentcontrol.AgentJob
import com.skaymer.gryonixnexus.agentcontrol.AgentJobKind
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOutcome
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOperations
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.app.servers.WrapperLogText
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DetachedJobs
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex

/** One long run the app is showing, whoever started it */
data class RunningJob(
    val id: String,
    val deploymentID: String,
    val title: String,
    val line: String = "",
    /** The last stage a known line announced */
    val stage: WrapperLogText.Stage? = null,
    val finished: Boolean = false,
    val failure: String? = null,
    val host: SSHHostID? = null,
    val kind: OperationKind = OperationKind.OTHER,
) {
    /** What identifies this run on the strip */
    val key: String get() = "$id@${host ?: "agent"}"

    fun withLine(text: String): RunningJob = copy(line = text, stage = WrapperLogText.stage(text) ?: stage)
}

class RunningJobs(
    private val scope: CoroutineScope,
    private val deployments: () -> List<Deployment>,
    private val operations: suspend (Deployment) -> AgentJobOperations,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    /** Plans a screen on this device already follows */
    private val followedHere: (String) -> Boolean = { false },
) {
    private val _jobs = MutableStateFlow<List<RunningJob>>(emptyList())
    val jobs: StateFlow<List<RunningJob>> = _jobs

    private val notices = mutableMapOf<String, OperationNotice?>()

    init {
        scope.launch { _jobs.collect(::mirror) }
    }

    /** One notification per adopted run, unless this device shows it */
    private fun mirror(jobs: List<RunningJob>) {
        for (job in jobs) {
            val deployment = deployments().firstOrNull { it.id.toString() == job.deploymentID }
            val server = deployment?.name.orEmpty()
            val notice = notices.getOrPut(job.key) { adopted(job, deployment, server) } ?: continue
            if (job.finished) {
                notice.finish(OperationNotices.text(R.string.notice_done), job.failure)
            } else {
                notice.update(job.line)
            }
        }
    }

    private fun adopted(job: RunningJob, deployment: Deployment?, server: String): OperationNotice? {
        if (OperationNotices.isShowing(server)) return null
        val notice = OperationNotices.startTitled(job.title, server, kind = job.kind)
        if (deployment != null && job.host == null && !job.finished) {
            notice.onStop { operations(deployment).cancel(job.id) }
        }
        return notice
    }

    /** One sweep at a time */
    private val sweeping = Mutex()

    fun sweep() {
        scope.launch {
            if (!sweeping.tryLock()) return@launch
            try {
                for (deployment in deployments()) {
                    adopt(deployment)
                    adoptDetached(deployment)
                }
            } finally {
                sweeping.unlock()
            }
        }
    }

    private suspend fun adopt(deployment: Deployment) {
        val ops = runCatching { operations(deployment) }.getOrNull() ?: return
        val running = runCatching { ops.jobs(runningOnly = true) }.getOrNull() ?: return
        for (job in running) {
            if (!shownAlone(job) || followedHere(job.id) || _jobs.value.any { it.id == job.id }) continue
            attach(job, deployment, ops)
        }
    }

    private suspend fun adoptDetached(deployment: Deployment) {
        val runner = runCatching { runners(deployment) }.getOrNull() ?: return
        for (host in journalHosts(deployment)) {
            val listed = runCatching {
                DetachedJobs.parseList(
                    runner.run(
                        DetachedJobs.listCommand(), host,
                        deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
                    ).stdout,
                )
            }.getOrNull() ?: continue
            for (job in listed) {
                val key = "${job.id}@$host"
                if (!job.isRunning || _jobs.value.any { it.key == key }) continue
                attachDetached(job, deployment, runner, host)
            }
        }
    }

    private fun attachDetached(
        job: DetachedJobs.Job,
        deployment: Deployment,
        runner: SSHCommandRunner,
        host: SSHHostID,
    ) {
        _jobs.value = _jobs.value + RunningJob(
            id = job.id,
            deploymentID = deployment.id.toString(),
            title = title(job, deployment),
            host = host,
            kind = OperationKind.of(job.kind),
        )
        scope.launch {
            var exit: Int? = null
            val failure = runCatching {
                runner.stream(
                    DetachedJobs.followCommand(job.id, 1), host,
                    deployment.timeouts.duration(ServiceCommand.TimeoutClass.LONG),
                ).collect { chunk ->
                    for (piece in chunk.text.split("\n")) {
                        if (piece.startsWith(DetachedJobs.EXIT_MARKER)) {
                            exit = piece.removePrefix(DetachedJobs.EXIT_MARKER).trim().toIntOrNull()
                            continue
                        }
                        val text = WrapperLogText.readable(piece).trim()
                        if (text.isNotEmpty()) update("${job.id}@$host") { it.withLine(text) }
                    }
                }
            }.exceptionOrNull()
            val code = exit
            update("${job.id}@$host") {
                it.copy(
                    finished = true,
                    failure = failure?.message
                        ?: when {
                            code == null -> "the log ended without saying how it went"
                            code != 0 -> "exit $code"
                            else -> null
                        },
                )
            }
        }
    }

    private fun attach(job: AgentJob, deployment: Deployment, ops: AgentJobOperations) {
        _jobs.value = _jobs.value + RunningJob(
            id = job.id,
            deploymentID = deployment.id.toString(),
            title = title(job, deployment),
            kind = OperationKind.of(job.kind),
        )
        scope.launch {
            val failure = followAgentJob(job, ops)
            update("${job.id}@agent") { it.copy(finished = true, failure = failure) }
        }
    }

    /** Follows a run, re-attaching; the failure text or null */
    private suspend fun followAgentJob(job: AgentJob, ops: AgentJobOperations): String? {
        var attempts = 0
        while (true) {
            val dropped = runCatching {
                ops.watch(job.id) { line ->
                    val text = WrapperLogText.readable(line).trim()
                    if (text.isNotEmpty()) update("${job.id}@agent") { it.withLine(text) }
                }
            }.exceptionOrNull() ?: return null
            val current = runCatching { ops.jobs().firstOrNull { it.id == job.id } }.getOrNull()
            when (current?.outcome) {
                AgentJobOutcome.SUCCEEDED, AgentJobOutcome.CANCELLED -> return null
                AgentJobOutcome.FAILED, AgentJobOutcome.ABANDONED ->
                    return current.failure.ifEmpty { dropped.message ?: dropped.toString() }
                else -> Unit
            }
            if (attempts++ >= REATTACH_TRIES) return dropped.message ?: dropped.toString()
            delay(REATTACH_DELAY_MS)
        }
    }

    private fun update(key: String, change: (RunningJob) -> RunningJob) {
        _jobs.value = _jobs.value.map { if (it.key == key) change(it) else it }
    }

    fun dismiss(key: String) {
        _jobs.value = _jobs.value.filterNot { it.key == key && it.finished }
    }

    companion object {
        private const val REATTACH_TRIES = 5
        private const val REATTACH_DELAY_MS = 3_000L

        /** A service run inside a plan shows there */
        fun shownAlone(job: AgentJob): Boolean = job.partOf.isEmpty()

        /** The machines whose detached-job journals are worth reading */
        fun journalHosts(deployment: Deployment): List<SSHHostID> =
            deployment.workerHosts

        /** What the strip calls this run */
        fun title(job: DetachedJobs.Job, deployment: Deployment): String {
            val subject = displaySubject(job.subject)
            return when (job.kind) {
                DetachedJobs.Kind.UPDATE -> "Updating $subject"
                DetachedJobs.Kind.BACKUP -> "Backing up $subject"
                DetachedJobs.Kind.RESTORE -> "Restoring $subject"
                DetachedJobs.Kind.UNINSTALL -> "Removing $subject"
                DetachedJobs.Kind.CONTROL -> "Working on $subject"
            }
        }

        fun title(job: AgentJob, deployment: Deployment): String {
            val subject = displaySubject(job.subject)
            return when (job.kind) {
                AgentJobKind.INSTALL -> "Installing $subject"
                AgentJobKind.REPAIR -> "Repairing ${deployment.name}"
                AgentJobKind.REINSTALL -> "Reinstalling ${deployment.name}"
                AgentJobKind.UPDATE, AgentJobKind.CONTAINER_UPDATE -> "Updating $subject"
                AgentJobKind.BACKUP, AgentJobKind.CONTAINER_BACKUP -> "Backing up $subject"
                AgentJobKind.RESTORE -> "Restoring $subject"
                AgentJobKind.UNINSTALL, AgentJobKind.CONTAINER_REMOVAL -> "Removing $subject"
                AgentJobKind.SERVICE_CONTROL, AgentJobKind.CONTAINER_CONTROL ->
                    "Working on $subject"
                AgentJobKind.MODEL_PULL -> "Fetching $subject"
                AgentJobKind.SECURITY_CONTROL -> "Protection on ${deployment.name}"
                AgentJobKind.AGENT_UPDATE -> "Updating the agent"
                AgentJobKind.MOVE -> "Moving $subject"
                AgentJobKind.UNKNOWN -> "Working on ${deployment.name}"
            }
        }

        /** Service names for a subject; a plan names several */
        fun displaySubject(subject: String): String {
            val parts = subject.split(" +", limit = 2)
            val names = parts[0].split(", ").joinToString(", ", transform = ::displayName)
            return if (parts.size == 2) "$names +${parts[1]}" else names
        }

        private fun displayName(id: String): String {
            val service = AgentServiceMapping.serviceIDs(listOf(id)).firstOrNull() ?: return id
            return ServiceRegistry.service(service)?.displayName ?: id
        }
    }
}

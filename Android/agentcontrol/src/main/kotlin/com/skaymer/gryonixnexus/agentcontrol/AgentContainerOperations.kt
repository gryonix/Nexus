package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.ContainerDatabaseEngine
import gryonixnexusd.v1.ContainerGroupKind
import gryonixnexusd.v1.ServiceAction
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.ServiceStatus
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class ContainerGroup(
    val key: String,
    val isComposeProject: Boolean,
    val displayName: String,
    val derivedName: String,
    val isRenamed: Boolean,
    val serviceID: String?,
    val status: ContainerGroupStatus,
    val containers: List<ContainerSummary>,
    val configFiles: List<String>,
)

/** How much of a group is up */
enum class ContainerGroupStatus {
    RUNNING,
    STOPPED,

    PARTIAL,
    ERROR,
    UNKNOWN,
}

/** One container inside a group */
data class ContainerSummary(
    val name: String,
    val image: String,
    /** "running", "exited", … — the engine's own word, not a parsed one */
    val state: String,
    val health: String,
    val ports: String,
)

data class ContainerInventory(
    val groups: List<ContainerGroup>,
    /** Non-null when the host has no reachable container engine */
    val unavailableReason: String?,
)

/** Everything about one container the list does not carry */
data class ContainerDetail(
    val container: ContainerSummary,
    val createdAt: String,
    val restartPolicy: String,
    /** Empty for a standalone container */
    val composeProject: String,
    val composeService: String,
    val command: String,
    val environment: List<ContainerEnvironmentVariable>,
    val mounts: List<ContainerMount>,
)

data class ContainerMount(
    /** The host path */
    val source: String,
    val destination: String,
    val isReadOnly: Boolean,
    /** "bind" | "volume", as the engine reports it */
    val kind: String,
    /** A named volume's name, empty for a bind mount */
    val volumeName: String = "",
) {
    val displaySource: String get() = volumeName.ifEmpty { source }
}

/** One environment variable of a container */
data class ContainerEnvironmentVariable(
    val key: String,
    val value: String,
    val isSensitive: Boolean,
)

/** What a backup of one group would archive */
data class ContainerBackupPlan(
    val key: String,
    val paths: List<String>,
    val volumes: List<String>,
    val databases: List<ContainerDatabaseDump>,
    /** Stop the stack while archiving */
    val stopWhileArchiving: Boolean,
    val isDetected: Boolean,
    /** What the detection concluded, in the server's words */
    val notes: List<String>,
)

data class ContainerDatabaseDump(
    val container: String,
    /** "postgres", "mysql", … as the agent classified the image */
    val engine: String,
    val database: String,
    val user: String,
    val passwordEnvName: String,
    internal val wireEngine: ContainerDatabaseEngine =
        ContainerDatabaseEngine.CONTAINER_DATABASE_ENGINE_UNSPECIFIED,
)

/** The three verbs, in the app's vocabulary */
enum class ContainerAction {
    START,
    STOP,
    RESTART;

    internal val wire: ServiceAction
        get() = when (this) {
            START -> ServiceAction.SERVICE_ACTION_START
            STOP -> ServiceAction.SERVICE_ACTION_STOP
            RESTART -> ServiceAction.SERVICE_ACTION_RESTART
        }
}

data class ContainerLogLine(
    val container: String,
    val text: String,
    /** "stdout" | "stderr" */
    val stream: String,
)

/** The phase of any streamed container verb */
enum class ContainerEventPhase {
    STARTED,
    PROGRESS,
    COMPLETED,
    UNKNOWN;

    internal companion object {
        fun of(wire: ServiceOperationPhase) = when (wire) {
            ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED -> STARTED
            ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS -> PROGRESS
            ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED -> COMPLETED
            else -> UNKNOWN
        }
    }
}

/** What a control run reports as it goes */
data class ContainerOperationEvent(
    val phase: ContainerEventPhase,
    val key: String,
    /** PROGRESS only */
    val text: String,
    val containers: List<String>,
    val group: ContainerGroup?,
)

/** One group's backups, and where the agent keeps them */
data class ContainerBackupListing(
    val key: String,
    val directory: String,
    val archives: List<ContainerArchive>,
)

/** One archive on the server */
data class ContainerArchive(
    val name: String,
    val path: String,
    val sizeBytes: Long,
    val modifiedAt: Instant?,
)

/** One event from a backup run */
data class ContainerBackupRunEvent(
    val phase: ContainerEventPhase,
    val key: String,
    val text: String,
    val stream: String,
    val plan: ContainerBackupPlan?,
    val archive: ContainerArchive?,
    /** COMPLETED only */
    val group: ContainerGroup?,
)

data class ContainerRemovalPreview(
    /** Always removed */
    val containers: List<String>,
    /** Removed only with `purgeData` */
    val volumes: List<String>,
    val paths: List<String>,
    /** Removed only with `purgeBackups` */
    val backupPaths: List<String>,
    val notes: List<String>,
) {
    val isEmpty: Boolean
        get() = containers.isEmpty() && volumes.isEmpty() && paths.isEmpty() && backupPaths.isEmpty()
}

data class ContainerRemovalEvent(
    val phase: ContainerEventPhase,
    val key: String,
    val text: String,
    val stream: String,
    /** STARTED only */
    val removing: ContainerRemovalPreview?,
    /** COMPLETED only */
    val group: ContainerGroup?,
)

data class ContainerUpdateEvent(
    val phase: ContainerEventPhase,
    val key: String,
    val text: String,
    val stream: String,
    val previousImages: Map<String, String>,
    /** COMPLETED only */
    val didRollBack: Boolean,
    val wasAlreadyCurrent: Boolean,
    val group: ContainerGroup?,
)

enum class ContainerBackupCadence(val wire: String) {
    DAILY("daily"),
    WEEKLY("weekly"),
    MONTHLY("monthly");

    internal companion object {
        fun of(wire: String) = entries.firstOrNull { it.wire == wire }
    }
}

data class ContainerBackupSchedule(
    val key: String,
    /** null when the group is not scheduled */
    val cadence: ContainerBackupCadence?,
    /** What the last scheduled run did, in the server's words */
    val lastOutcome: String,
    val lastRun: Instant?,
) {
    val isEnabled: Boolean get() = cadence != null
}

class AgentContainerOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun inventory(): ContainerInventory = inventory(gate.gated { client.listContainers() })

    suspend fun rename(key: String, to: String): ContainerInventory =
        inventory(gate.gated { client.setContainerGroupName(key, to.trim()) })

    fun control(key: String, action: ContainerAction): Flow<ContainerOperationEvent> =
        client.controlContainerGroup(key, action.wire).map { wire ->
            ContainerOperationEvent(
                phase = ContainerEventPhase.of(wire.phase),
                key = wire.key,
                text = wire.text,
                containers = wire.containers,
                group = wire.group?.let(::group),
            )
        }

    /** Follows one group's containers */
    fun logs(key: String, tail: Int = 0): Flow<ContainerLogLine> =
        client.containerGroupLogs(key, tail).map {
            ContainerLogLine(container = it.container, text = it.text, stream = it.stream)
        }

    /** Everything about one container the list does not carry */
    suspend fun inspect(container: String): ContainerDetail {
        val detail = gate.gated { client.inspectContainer(container) }
        return ContainerDetail(
            container = detail.container?.let(::summary)
                ?: ContainerSummary(container, "", "", "", ""),
            createdAt = detail.created_at,
            restartPolicy = detail.restart_policy,
            composeProject = detail.compose_project,
            composeService = detail.compose_service,
            command = detail.command,
            environment = detail.env.map {
                ContainerEnvironmentVariable(it.key, it.value_, it.sensitive)
            },
            mounts = detail.mounts.map {
                ContainerMount(
                    source = it.source,
                    destination = it.destination,
                    isReadOnly = it.mode == "ro",
                    kind = it.kind,
                    volumeName = it.name,
                )
            },
        )
    }

    suspend fun backupPlan(key: String): ContainerBackupPlan =
        planOf(gate.gated { client.containerBackupPlan(key) })

    suspend fun setBackupPlan(key: String, plan: ContainerBackupPlan?): ContainerBackupPlan =
        planOf(gate.gated { client.setContainerBackupPlan(key, plan?.let { wire(it, key) }) })

    /** Runs the plan, streaming what it does */
    fun runBackup(key: String): Flow<ContainerBackupRunEvent> =
        client.runContainerGroupBackup(key).map { wire ->
            ContainerBackupRunEvent(
                phase = ContainerEventPhase.of(wire.phase),
                key = wire.key,
                text = wire.text,
                stream = wire.stream,
                plan = wire.plan?.let(::planOf),
                archive = wire.archive?.let(::archive),
                group = wire.group?.let(::group),
            )
        }

    /** What removing this group would delete, for these toggles */
    suspend fun removalPreview(
        key: String,
        purgeData: Boolean,
        purgeBackups: Boolean,
    ): ContainerRemovalPreview =
        preview(gate.gated { client.previewContainerGroupRemoval(key, purgeData, purgeBackups) })

    fun remove(key: String, purgeData: Boolean, purgeBackups: Boolean): Flow<ContainerRemovalEvent> =
        client.removeContainerGroup(key, purgeData, purgeBackups).map { wire ->
            ContainerRemovalEvent(
                phase = ContainerEventPhase.of(wire.phase),
                key = wire.key,
                text = wire.text,
                stream = wire.stream,
                removing = wire.removing?.let(::preview),
                group = wire.group?.let(::group),
            )
        }

    fun update(key: String, skipBackup: Boolean = false): Flow<ContainerUpdateEvent> =
        client.updateContainerGroup(key, skipBackup).map { wire ->
            ContainerUpdateEvent(
                phase = ContainerEventPhase.of(wire.phase),
                key = wire.key,
                text = wire.text,
                stream = wire.stream,
                previousImages = wire.previous_images,
                didRollBack = wire.rolled_back,
                wasAlreadyCurrent = wire.already_current,
                group = wire.group?.let(::group),
            )
        }

    suspend fun backupSchedule(key: String): ContainerBackupSchedule =
        schedule(gate.gated { client.containerBackupSchedule(key) })

    /** Sets it, or switches it off with a null [every] */
    suspend fun setBackupSchedule(key: String, every: ContainerBackupCadence?): ContainerBackupSchedule =
        schedule(gate.gated { client.setContainerBackupSchedule(key, every?.wire.orEmpty()) })

    /** The archives one foreign group's backups have left, newest first */
    suspend fun backups(key: String): ContainerBackupListing =
        gate.gated { client.containerGroupBackups(key) }.let { wire ->
            ContainerBackupListing(
                key = wire.key,
                directory = wire.directory,
                archives = wire.archives.map(::archive),
            )
        }

    // --------------------------------------------------------------- Mapping

    internal companion object {
        internal fun inventory(wire: gryonixnexusd.v1.ContainerInventory) = ContainerInventory(
            groups = wire.groups.map(::group),
            unavailableReason = wire.unavailable_reason.ifEmpty { null },
        )

        internal fun summary(wire: gryonixnexusd.v1.Container) = ContainerSummary(
            name = wire.name,
            image = wire.image,
            state = wire.state,
            health = wire.health,
            ports = wire.ports,
        )

        internal fun group(wire: gryonixnexusd.v1.ContainerGroup) = ContainerGroup(
            key = wire.key,
            isComposeProject = wire.kind == ContainerGroupKind.CONTAINER_GROUP_KIND_COMPOSE_PROJECT,
            displayName = wire.display_name,
            derivedName = wire.derived_name,
            isRenamed = wire.renamed,
            serviceID = wire.service_id.ifEmpty { null },
            status = when (wire.status) {
                ServiceStatus.SERVICE_STATUS_RUNNING -> ContainerGroupStatus.RUNNING
                ServiceStatus.SERVICE_STATUS_STOPPED -> ContainerGroupStatus.STOPPED
                ServiceStatus.SERVICE_STATUS_PARTIAL -> ContainerGroupStatus.PARTIAL
                ServiceStatus.SERVICE_STATUS_ERROR -> ContainerGroupStatus.ERROR
                else -> ContainerGroupStatus.UNKNOWN
            },
            containers = wire.containers.map(::summary),
            configFiles = wire.config_files,
        )

        internal fun planOf(wire: gryonixnexusd.v1.ContainerBackupPlan) = ContainerBackupPlan(
            key = wire.key,
            paths = wire.paths,
            volumes = wire.volumes,
            databases = wire.databases.map {
                ContainerDatabaseDump(
                    container = it.container,
                    engine = engineName(it.engine),
                    database = it.database,
                    user = it.user,
                    passwordEnvName = it.password_env,
                    wireEngine = it.engine,
                )
            },
            stopWhileArchiving = wire.stop_while_archiving,
            isDetected = wire.detected,
            notes = wire.notes,
        )

        internal fun engineName(engine: ContainerDatabaseEngine): String =
            engine.name.removePrefix("CONTAINER_DATABASE_ENGINE_").lowercase()

        /** Back to the wire, for a correction */
        internal fun wire(plan: ContainerBackupPlan, key: String) = gryonixnexusd.v1.ContainerBackupPlan(
            key = key,
            paths = plan.paths,
            volumes = plan.volumes,
            databases = plan.databases.map {
                gryonixnexusd.v1.ContainerDatabaseDump(
                    container = it.container,
                    engine = it.wireEngine,
                    database = it.database,
                    user = it.user,
                    password_env = it.passwordEnvName,
                )
            },
            stop_while_archiving = plan.stopWhileArchiving,
        )

        internal fun archive(wire: gryonixnexusd.v1.BackupArchive) = ContainerArchive(
            name = wire.name,
            path = wire.path,
            sizeBytes = wire.size_bytes,
            modifiedAt = wire.modified_at.takeIf { it > 0 }?.let(Instant::ofEpochMilli),
        )

        internal fun preview(wire: gryonixnexusd.v1.ContainerRemovalPreview) = ContainerRemovalPreview(
            containers = wire.containers,
            volumes = wire.volumes,
            paths = wire.paths,
            backupPaths = wire.backup_paths,
            notes = wire.notes,
        )

        internal fun schedule(wire: gryonixnexusd.v1.ContainerBackupSchedule) = ContainerBackupSchedule(
            key = wire.key,
            cadence = ContainerBackupCadence.of(wire.schedule),
            lastOutcome = wire.last_outcome,
            lastRun = wire.last_run.toLongOrNull()?.takeIf { it > 0 }?.let(Instant::ofEpochSecond),
        )
    }
}

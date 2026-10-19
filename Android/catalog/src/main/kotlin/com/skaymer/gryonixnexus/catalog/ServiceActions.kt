package com.skaymer.gryonixnexus.catalog

class ServiceActions(
    val statusProbe: StatusProbe,
    /** Destructive — the UI confirms before running */
    val restart: ServiceCommand? = null,
    /** Brings the whole service up again after [stop] */
    val start: ServiceCommand? = null,
    val stop: ServiceCommand? = null,
    val backup: BackupSpec? = null,
    val restore: RestoreSpec? = null,
    logs: ServiceCommand? = null
) {
    /** Reading this service's container log */
    val logs: ServiceCommand? = logs ?: ServicePower.containerLogs(statusProbe)
}

object ServicePower {
    fun compose(project: String, verb: String,
                timeoutClass: ServiceCommand.TimeoutClass = ServiceCommand.TimeoutClass.RESTART):
        ServiceCommand =
        ServiceCommand(
            PrivilegedCommand("/usr/bin/docker", "compose -p $project $verb"),
            timeoutClass
        )

    fun container(name: String, verb: String,
                  timeoutClass: ServiceCommand.TimeoutClass = ServiceCommand.TimeoutClass.RESTART):
        ServiceCommand =
        ServiceCommand(PrivilegedCommand("/usr/bin/docker", "$verb $name"), timeoutClass)

    fun containerLogs(probe: StatusProbe): ServiceCommand {
        val arguments = when (probe) {
            is StatusProbe.Container -> "logs --tail 500 --timestamps ${probe.name}"
            is StatusProbe.ComposeProject ->
                "compose -p ${probe.project} logs --tail 500 --timestamps"
        }
        return ServiceCommand(
            PrivilegedCommand("/usr/bin/docker", arguments),
            ServiceCommand.TimeoutClass.QUICK,
            streamsOutput = true
        )
    }
}

/** How to read the service's health */
sealed class StatusProbe {
    /** `sudo docker compose -p <project> ps` — one row per container */
    data class ComposeProject(val project: String, val list: PrivilegedCommand) : StatusProbe()

    data class Container(val name: String, val list: PrivilegedCommand) : StatusProbe()

    val privilegedCommands: List<PrivilegedCommand>
        get() = when (this) {
            is ComposeProject -> listOf(list)
            is Container -> listOf(list)
        }
}

data class ServiceCommand(
    val privileged: PrivilegedCommand,
    val timeoutClass: TimeoutClass,
    val streamsOutput: Boolean = false,
    val workingDirectory: String? = null
) {
    enum class TimeoutClass { QUICK, RESTART, LONG }

    val command: String
        get() = workingDirectory?.let { "cd $it && ${privileged.command}" } ?: privileged.command
}

/** How a service is put back from a backup */
data class RestoreSpec(
    /** Service label passed to the wrapper as its first argument */
    val wrapperTarget: String,
    /** Directory the app lists restorable backups from, and uploads into */
    val backupDir: String,
    val needsPassphrase: Boolean,
    val privileged: PrivilegedCommand
) {
    /** Whether restoring THIS archive needs a passphrase */
    fun needsPassphrase(archivePath: String): Boolean =
        needsPassphrase || archivePath.endsWith(ENCRYPTED_SUFFIX)

    companion object {
        /** The one wrapper every restore goes through */
        const val WRAPPER_PATH = "/opt/gryonixnexus-restore.sh"

        /** Suffix the wrapper (and gpg) recognise as an encrypted archive */
        const val ENCRYPTED_SUFFIX = ".gpg"
    }
}

/** Backup flavours */
sealed class BackupSpec {
    data class WrapperScript(val spec: BackupWrapperSpec) : BackupSpec()

    data class EncryptedVolume(
        val container: String,
        val dataPath: String,
        val backupDir: String,
        val stopStart: EncryptedVolumeCommands
    ) : BackupSpec()

    /** Directory the app lists this service's backups from */
    val listDirectory: String
        get() = when (this) {
            is WrapperScript -> spec.backupDir
            is EncryptedVolume -> backupDir
        }

    val wrapper: BackupWrapperSpec? get() = (this as? WrapperScript)?.spec

    val encryptsByDefault: Boolean
        get() = when (this) {
            is WrapperScript -> spec.encryptsByDefault
            is EncryptedVolume -> true
        }

    fun privilegedCommands(context: ServiceContext): List<PrivilegedCommand> = when (this) {
        is WrapperScript -> listOf(spec.run.privileged)
        is EncryptedVolume -> {
            val staging = stagingArchivePath(backupDir, container)
            listOf(
                stopStart.stop,
                stopStart.start,
                PrivilegedCommand("/bin/tar", archiveArguments(dataPath, staging)),
                PrivilegedCommand("/bin/chown", "${context.sshUser} $staging")
            )
        }
    }

    companion object {
        fun stagingArchivePath(backupDir: String, container: String): String =
            "$backupDir/$container-backup.tar.gz"

        /** tar's argument vector, in the order sudo matches it */
        fun archiveArguments(dataPath: String, archivePath: String): String =
            "czf $archivePath -C / ${archiveRelativePath(dataPath)}"

        /** [dataPath] without its leading slash — what tar receives after `-C /` */
        fun archiveRelativePath(dataPath: String): String = dataPath.removePrefix("/")
    }
}

data class EncryptedVolumeCommands(
    val stop: PrivilegedCommand,
    val start: PrivilegedCommand
)

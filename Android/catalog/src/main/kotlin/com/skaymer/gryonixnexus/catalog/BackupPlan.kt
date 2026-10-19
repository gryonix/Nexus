package com.skaymer.gryonixnexus.catalog

data class BackupWrapperSpec(
    /** Service label passed to the wrapper */
    val wrapperTarget: String,
    /** Directory the app lists backups from, and uploads into */
    val backupDir: String,
    /** The whitelisted invocation the app sends */
    val run: ServiceCommand,
    /** What the wrapper actually does for this service */
    val plan: BackupPlan
) {
    val encryptsByDefault: Boolean get() = plan.encryptsByDefault

    /** Paths whose on-disk size the estimate sums before a run */
    val sizePaths: List<String> get() = plan.sizePaths

    companion object {
        /** The one wrapper every wrapper-driven backup goes through */
        const val WRAPPER_PATH = "/opt/gryonixnexus-backup-ctl.sh"
    }
}

/** The two shapes a wrapper-driven backup takes */
sealed class BackupPlan {
    data class ExternalScript(val path: String, override val sizePaths: List<String>) : BackupPlan() {
        override val encryptsByDefault: Boolean get() = false
    }

    /** The wrapper builds the archive itself, from the description below */
    data class Archive(val plan: ArchiveBackupPlan) : BackupPlan() {
        override val encryptsByDefault: Boolean get() = plan.encryptsByDefault
        override val sizePaths: List<String> get() = plan.sizePaths
    }

    abstract val encryptsByDefault: Boolean
    abstract val sizePaths: List<String>

    val archive: ArchiveBackupPlan? get() = (this as? Archive)?.plan
}

data class ArchiveBackupPlan(
    /** Compose project the stop/start and `exec` commands address */
    val composeProject: String,
    val dataPath: String,
    /** Databases dumped through their own client instead of archived */
    val databases: List<BackupDatabase> = emptyList(),
    val quiesceServices: List<String> = emptyList(),
    /** GPG unless the caller says otherwise */
    val encryptsByDefault: Boolean,
    val sizePaths: List<String>,
    val excludes: List<String> = emptyList()
) {
    val dataSlot: String
        get() = dataPath.split("/").lastOrNull()?.takeIf { it.isNotEmpty() } ?: dataPath

    val dataParent: String
        get() {
            val trimmed = dataPath.removeSuffix("/")
            val slash = trimmed.lastIndexOf('/')
            if (slash <= 0) return "/"
            return trimmed.substring(0, slash)
        }

    companion object {
        /** Directory holding the dumps inside the archive */
        const val DUMP_DIRECTORY_NAME = "gryonixnexus-db"
    }
}

/** One database dumped through its own client */
data class BackupDatabase(
    val engine: Engine,
    /** Compose service name of the database container */
    val service: String,
    /** File name inside the archive's dump directory */
    val fileName: String,
    /** Which database inside that engine to dump */
    val databaseName: String? = null
) {
    enum class Engine(val wireValue: String) {
        /** Dumped with `pg_dump`, loaded with `psql` */
        POSTGRES("postgres"),

        MYSQL("mysql")
    }
}

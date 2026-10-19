package com.skaymer.gryonixnexus.servercontrol

data class BackupEstimate(
    /** On-disk size of everything the run would archive, before compression */
    val dataBytes: Long,
    /** Free space on the filesystem holding the backup directory */
    val freeBytes: Long,
) {
    val fitsOnDisk: Boolean get() = freeBytes > dataBytes

    companion object {
        fun parse(output: String): BackupEstimate? {
            val line = output.split("\n")
                .firstOrNull { it.startsWith(CommandMarkers.Backups.ESTIMATE) } ?: return null
            val fields = line.split(" ").filter { it.isNotEmpty() }
            if (fields.size < 3) return null
            val data = fields[1].toLongOrNull() ?: return null
            val free = fields[2].toLongOrNull() ?: return null
            return BackupEstimate(data, free)
        }
    }
}

/** The result of one wrapper-driven backup */
data class BackupOutcome(
    /** Size of the finished archive */
    val sizeBytes: Long?,
    val path: String?,
    /** The streamed output, tailed for display */
    val log: String,
) {
    companion object {
        /** Reads the wrapper's `GRYONIXNEXUS_BACKUP_DONE <bytes> <path>` line */
        fun parse(output: String, log: String): BackupOutcome? {
            val line = output.split("\n")
                .lastOrNull { it.startsWith(CommandMarkers.Backups.BACKUP_DONE) } ?: return null
            val fields = line.split(" ", limit = 3)
            if (fields.size != 3) return null
            val size = fields[1].toLongOrNull() ?: return null
            return BackupOutcome(size, fields[2].trim(), log)
        }
    }
}

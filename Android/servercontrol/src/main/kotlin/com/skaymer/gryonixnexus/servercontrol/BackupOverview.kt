package com.skaymer.gryonixnexus.servercontrol

/** One backup with the server and service it belongs to */
data class FleetBackup(
    val serverId: String,
    val serverName: String,
    val serviceId: String,
    val serviceName: String,
    val entry: BackupEntry,
) {
    val id: String get() = "$serverId/$serviceId/${entry.drive.orEmpty()}/${entry.name}"
}

/** Which backups a list shows */
data class BackupFilter(
    val serviceId: String? = null,
    val place: Place = Place.ANY,
) {
    enum class Place {
        ANY, SERVER, DRIVES;

        fun admits(entry: BackupEntry): Boolean = when (this) {
            ANY -> true
            SERVER -> entry.drive == null
            DRIVES -> entry.drive != null
        }
    }

    fun admits(row: FleetBackup): Boolean {
        if (serviceId != null && row.serviceId != serviceId) return false
        return place.admits(row.entry)
    }
}

/** Counts and sizes over a set of backups */
data class BackupTotals(
    val count: Int = 0,
    val bytes: Long = 0,
    val onDrives: Int = 0,
    val newestMillis: Long? = null,
    /** Backups without a known size */
    val unsized: Int = 0,
)

object BackupOverview {
    /** Newest first; undated ones stay last */
    fun sorted(rows: List<FleetBackup>): List<FleetBackup> =
        rows.sortedWith(compareByDescending<FleetBackup, Long?>(nullsFirst()) { it.entry.modifiedAtMillis })

    fun filtered(rows: List<FleetBackup>, filter: BackupFilter): List<FleetBackup> =
        rows.filter(filter::admits)

    fun totals(rows: List<FleetBackup>): BackupTotals {
        var totals = BackupTotals()
        for (row in rows) {
            val size = row.entry.sizeBytes
            val time = row.entry.modifiedAtMillis
            totals = totals.copy(
                count = totals.count + 1,
                onDrives = totals.onDrives + if (row.entry.drive != null) 1 else 0,
                bytes = totals.bytes + (size ?: 0),
                unsized = totals.unsized + if (size == null && !row.entry.isDirectory) 1 else 0,
                newestMillis = listOfNotNull(totals.newestMillis, time).maxOrNull(),
            )
        }
        return totals
    }
}

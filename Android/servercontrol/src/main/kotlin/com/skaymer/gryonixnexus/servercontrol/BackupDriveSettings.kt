package com.skaymer.gryonixnexus.servercontrol

/** Which USB drives take a copy, and how */
data class BackupDriveSettings(
    val mode: Mode = Mode.BOTH,
    /** Encrypt copies on the drives */
    val encrypt: Boolean = true,
    /** Filesystem UUIDs of the drives in use */
    val uuids: List<String> = emptyList(),
) {
    enum class Mode(val wire: String) { BOTH("both"), LOCAL("local"), DRIVE("drive") }
}

/** One chosen drive, as the server sees it now */
data class BackupDriveStatus(
    val uuid: String,
    val mounted: Boolean = false,
    val sizeBytes: Long = 0,
    val freeBytes: Long = 0,
    val mountPoint: String = "",
) {
    /** The drive's name: the last part of its mount point */
    val name: String get() = mountPoint.substringAfterLast('/').ifEmpty { uuid }
}

/** Drive settings, drives and the last copy, read back */
data class BackupDrivesState(
    val settings: BackupDriveSettings = BackupDriveSettings(),
    val statuses: List<BackupDriveStatus> = emptyList(),
    /** Unix seconds of the last copy, 0 when none */
    val lastCopyAt: Long = 0,
    val lastCopySucceeded: Boolean = false,
    val lastError: String = "",
    val hasPassphrase: Boolean = false,
    /** False when the server's wrapper predates USB drives */
    val supported: Boolean = true,
) {
    /** Drive names by UUID, for unplugged drives */
    val namesByUuid: Map<String, String> get() = statuses.associate { it.uuid to it.name }

    /** Settings with a newly formatted drive replacing its predecessors */
    fun settingsAfterFormat(uuid: String, replacing: String?, name: String): BackupDriveSettings {
        val names = namesByUuid
        val kept = settings.uuids.filter { it != uuid && it != replacing && names[it] != name }
        return settings.copy(uuids = kept + uuid)
    }

    /** Whether the server keeps no mount point for this drive */
    fun isUnmapped(uuid: String): Boolean = statuses.firstOrNull { it.uuid == uuid }?.mountPoint.isNullOrEmpty()
}

/** Parsing of what the wrapper's `show-drives` prints */
object BackupDrivesParsing {
    fun parse(output: String): BackupDrivesState = output.lines().fold(BackupDrivesState()) { state, line ->
        val key = line.substringBefore('=', "").trim()
        val value = line.substringAfter('=', "").trim('\'', '"', ' ')
        if (key.isEmpty()) state else apply(key, value, state)
    }

    private fun apply(key: String, value: String, state: BackupDrivesState): BackupDrivesState = when (key) {
        "DRIVE_MODE" -> state.copy(
            settings = state.settings.copy(
                mode = BackupDriveSettings.Mode.entries.firstOrNull { it.wire == value } ?: BackupDriveSettings.Mode.BOTH,
            ),
        )
        "DRIVE_ENCRYPT" -> state.copy(settings = state.settings.copy(encrypt = value != "0"))
        "DRIVES" -> state.copy(settings = state.settings.copy(uuids = value.split(" ").filter { it.isNotEmpty() }))
        "DRIVE_PASS" -> state.copy(hasPassphrase = value == "1")
        "DRIVE" -> status(value)?.let { state.copy(statuses = state.statuses + it) } ?: state
        "DRIVE_AT" -> state.copy(lastCopyAt = value.toLongOrNull() ?: 0)
        "DRIVE_OK" -> state.copy(lastCopySucceeded = value == "1")
        "DRIVE_ERROR" -> state.copy(lastError = value)
        else -> state
    }

    /** `<uuid> <mounted> <size> <free> <mount point>` */
    private fun status(value: String): BackupDriveStatus? {
        val fields = value.split(" ", limit = 5)
        if (fields.size < 4) return null
        return BackupDriveStatus(
            uuid = fields[0],
            mounted = fields[1] == "1",
            sizeBytes = fields[2].toLongOrNull() ?: 0,
            freeBytes = fields[3].toLongOrNull() ?: 0,
            mountPoint = fields.getOrElse(4) { "" },
        )
    }
}

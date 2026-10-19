package com.skaymer.gryonixnexus.servercontrol

data class BackupDestinationSettings(
    val kind: Kind = Kind.NONE,
    /** ssh/sftp: the host */
    val host: String = "",
    val port: Int = 22,
    val user: String = "",
    val path: String = "",
    val bucket: String = "",
    /** How many copies to keep ON THE DESTINATION */
    val keep: Int = 0,
) {
    enum class Kind(val wire: String) {
        NONE("none"),
        /** Another host over SSH, with a key this server owns */
        SSH("ssh"),
        /** Any S3-compatible bucket, through rclone on the server */
        S3("s3"),
        ;

        companion object {
            fun of(raw: String?): Kind = entries.firstOrNull { it.wire == raw } ?: NONE
        }
    }

    /** Whether this says enough to copy anything anywhere */
    val isConfigured: Boolean
        get() = when (kind) {
            Kind.NONE -> false
            Kind.SSH -> host.trim().isNotEmpty() && user.trim().isNotEmpty()
            Kind.S3 -> bucket.trim().isNotEmpty()
        }
}

data class BackupDestinationState(
    val settings: BackupDestinationSettings = BackupDestinationSettings(),
    val publicKey: String = "",
    val lastShipmentAt: Long? = null,
    val lastShipmentSucceeded: Boolean = false,
    /** The far side's own words */
    val lastError: String = "",
)

/** What a check of the destination came back with */
data class BackupDestinationTestResult(
    val succeeded: Boolean,
    val detail: String = "",
)

object BackupDestinationParsing {
    fun parse(output: String): BackupDestinationState {
        var settings = BackupDestinationSettings()
        var publicKey = ""
        var at: Long? = null
        var ok = false
        var error = ""
        for (line in output.split("\n")) {
            val parts = line.split("=", limit = 2)
            if (parts.size != 2) continue
            val value = parts[1].trim().trim('\'', '"')
            when (parts[0].trim()) {
                "DEST_KIND" -> settings = settings.copy(kind = BackupDestinationSettings.Kind.of(value))
                "DEST_HOST" -> settings = settings.copy(host = value)
                "DEST_PORT" -> settings = settings.copy(port = value.toIntOrNull() ?: 22)
                "DEST_USER" -> settings = settings.copy(user = value)
                "DEST_PATH" -> settings = settings.copy(path = value)
                "DEST_BUCKET" -> settings = settings.copy(bucket = value)
                "DEST_KEEP" -> settings = settings.copy(keep = value.toIntOrNull() ?: 0)
                "DEST_PUBKEY" -> publicKey = value
                "AT" -> at = value.toLongOrNull()?.takeIf { it > 0 }
                "OK" -> ok = value == "1"
                "ERROR" -> error = value
            }
        }
        return BackupDestinationState(settings, publicKey, at, ok, error)
    }

    fun parseTest(output: String, fallback: String = ""): BackupDestinationTestResult {
        val line = output.split("\n").lastOrNull { it.startsWith(DEST_TEST_MARKER) }
            ?: return BackupDestinationTestResult(false, OutputTail.tail(fallback))
        val parts = line.split(" ", limit = 3)
        return BackupDestinationTestResult(
            succeeded = parts.size > 1 && parts[1] == "1",
            detail = if (parts.size > 2) parts[2] else "",
        )
    }

    const val DEST_TEST_MARKER = "GRYONIXNEXUS_DEST_TEST"
}

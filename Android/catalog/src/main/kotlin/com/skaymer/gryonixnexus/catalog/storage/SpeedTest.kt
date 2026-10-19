package com.skaymer.gryonixnexus.catalog.storage

import kotlinx.serialization.Serializable

/** Disk and internet speed of a server */
object SpeedTest {
    const val DONE_MARKER = "GRYONIXNEXUS_SPEED_DONE"
    /** On the system disk and writable without root */
    const val SYSTEM_DIRECTORY = "/var/tmp"
    private const val DISK_MEGABYTES = 256
    private const val DOWNLOAD_BYTES = 50_000_000
    private const val UPLOAD_BYTES = 25_000_000
    private const val ENDPOINT = "https://speed.cloudflare.com"

    @Serializable
    data class DiskResult(
        val writeBytesPerSecond: Double,
        val readBytesPerSecond: Double,
        /** Direct I/O refused; numbers include the page cache */
        val cached: Boolean,
    )

    @Serializable
    data class InternetResult(
        val downloadBitsPerSecond: Double,
        val uploadBitsPerSecond: Double,
        val latencySeconds: Double,
    )

    /** Writes and reads a temporary file in `directory` */
    fun diskScript(directory: String): String {
        val dd = "LC_ALL=C dd bs=1M"
        return listOf(
            "#!/bin/bash",
            "set -uo pipefail",
            "F=${FastStoragePlan.quoted(directory)}/.gryonixnexus-speedtest.\$\$",
            "trap 'rm -f \"\$F\"' EXIT",
            "if w=\$($dd if=/dev/zero of=\"\$F\" count=$DISK_MEGABYTES oflag=direct conv=fdatasync 2>&1); then",
            "  r=\$($dd if=\"\$F\" of=/dev/null iflag=direct 2>&1); mode=direct",
            "else",
            "  w=\$($dd if=/dev/zero of=\"\$F\" count=$DISK_MEGABYTES conv=fdatasync 2>&1)",
            "  r=\$($dd if=\"\$F\" of=/dev/null 2>&1); mode=cached",
            "fi",
            "echo \"write \$(printf '%s' \"\$w\" | tail -n 1)\"",
            "echo \"read \$(printf '%s' \"\$r\" | tail -n 1)\"",
            "echo \"mode \$mode\"",
            "echo $DONE_MARKER",
        ).joinToString("\n") + "\n"
    }

    /** Downloads and uploads against a public speed endpoint */
    val INTERNET_SCRIPT: String = listOf(
        "#!/bin/bash",
        "set -uo pipefail",
        "command -v curl >/dev/null 2>&1 || { echo nocurl; exit 0; }",
        "echo \"down \$(curl -s -o /dev/null -w '%{speed_download} %{http_code}' --max-time 20 '$ENDPOINT/__down?bytes=$DOWNLOAD_BYTES'; true)\"",
        "echo \"up \$(head -c $UPLOAD_BYTES /dev/zero | curl -s -o /dev/null -w '%{speed_upload} %{http_code}' --max-time 20 --data-binary @- '$ENDPOINT/__up'; true)\"",
        "echo \"ping \$(curl -s -o /dev/null -w '%{time_connect}' --max-time 10 '$ENDPOINT/__down?bytes=0'; true)\"",
        "echo $DONE_MARKER",
    ).joinToString("\n") + "\n"

    fun parseDisk(output: String): DiskResult? {
        val fields = keyed(output)
        val write = fields["write"]?.let(::ddRate) ?: return null
        val read = fields["read"]?.let(::ddRate) ?: return null
        return DiskResult(write, read, fields["mode"] == "cached")
    }

    fun parseInternet(output: String): InternetResult? {
        val fields = keyed(output)
        val down = fields["down"]?.let(::answered) ?: 0.0
        val up = fields["up"]?.let(::answered) ?: 0.0
        if (down <= 0 && up <= 0) return null
        return InternetResult(down * 8, up * 8, fields["ping"]?.toDoubleOrNull() ?: 0.0)
    }

    /** Bytes per second from "rate code", only for HTTP 200 */
    internal fun answered(field: String): Double? {
        val parts = field.split(" ")
        if (parts.size != 2 || parts[1] != "200") return null
        return parts[0].toDoubleOrNull()
    }

    /** Bytes per second from dd's summary line */
    internal fun ddRate(line: String): Double? {
        val words = line.split(" ").filter { it.isNotEmpty() }
        val bytes = words.firstOrNull()?.toDoubleOrNull() ?: return null
        val copied = words.indexOfFirst { it.startsWith("copied") }.takeIf { it >= 0 } ?: return null
        val seconds = words.getOrNull(copied + 1)?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        return bytes / seconds
    }

    private fun keyed(output: String): Map<String, String> =
        output.split("\n").mapNotNull { line ->
            val space = line.indexOf(' ').takeIf { it > 0 } ?: return@mapNotNull null
            line.substring(0, space) to line.substring(space + 1).trim()
        }.toMap()
}

package com.skaymer.gryonixnexus.servercontrol

import java.time.LocalDateTime
import java.time.ZoneId

object BackupListParser {
    const val DEFAULT_LIMIT = 10

    fun parse(output: String, limit: Int = DEFAULT_LIMIT): List<BackupEntry> {
        val entries = mutableListOf<BackupEntry>()
        for (line in output.split("\n")) {
            if (!line.startsWith("-") && !line.startsWith("d")) continue
            val fields = line.split(" ").filter { it.isNotEmpty() }
            if (fields.size < 9) continue
            val name = nameAfterMetadataColumns(line) ?: continue
            entries += BackupEntry(
                name = name,
                sizeText = fields[4],
                dateText = fields.subList(5, 8).joinToString(" "),
                isDirectory = line.startsWith("d"),
                sizeBytes = if (line.startsWith("d")) null else approximateBytes(fields[4]),
                modifiedAtMillis = approximateDate(fields.subList(5, 8)),
            )
            if (entries.size == limit) break
        }
        return entries
    }

    /** Bytes from an `ls -h` size such as 1.2G */
    fun approximateBytes(text: String): Long? {
        val units = mapOf('K' to 1_024.0, 'M' to 1_048_576.0, 'G' to 1_073_741_824.0, 'T' to 1_099_511_627_776.0)
        val unit = units[text.lastOrNull()] ?: return text.toLongOrNull()
        return text.dropLast(1).toDoubleOrNull()?.let { (it * unit).toLong() }
    }

    /** Date from the three `ls` date columns */
    fun approximateDate(
        columns: List<String>,
        now: LocalDateTime = LocalDateTime.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Long? {
        if (columns.size != 3) return null
        val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
        val month = months.indexOf(columns[0]) + 1
        val day = columns[1].toIntOrNull()
        if (month == 0 || day == null) return null
        return runCatching {
            if (columns[2].contains(":")) {
                val clock = columns[2].split(":").map { it.toInt() }
                var date = LocalDateTime.of(now.year, month, day, clock[0], clock[1])
                // A time without a year is within six months
                if (date.isAfter(now.plusDays(1))) date = date.minusYears(1)
                date.atZone(zone).toInstant().toEpochMilli()
            } else {
                LocalDateTime.of(columns[2].toInt(), month, day, 0, 0).atZone(zone).toInstant().toEpochMilli()
            }
        }.getOrNull()
    }

    private fun nameAfterMetadataColumns(line: String): String? {
        var index = 0
        repeat(8) {
            while (index < line.length && line[index] != ' ') index++
            while (index < line.length && line[index] == ' ') index++
        }
        return if (index < line.length) line.substring(index) else null
    }
}

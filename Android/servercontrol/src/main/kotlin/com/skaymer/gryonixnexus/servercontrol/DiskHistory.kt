package com.skaymer.gryonixnexus.servercontrol

import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** One filesystem's use at one moment of history */
data class DiskHistoryPoint(val date: Instant, val mount: String, val usedBytes: Long, val totalBytes: Long) {
    val usedPercent: Double get() = if (totalBytes > 0) usedBytes.toDouble() / totalBytes * 100 else 0.0
}

/** Which disks a disk chart draws */
sealed interface DiskChoice {
    data object Average : DiskChoice
    data object Each : DiskChoice
    data class One(val mount: String) : DiskChoice
}

/** A named line of used percent over time */
data class DiskLine(val name: String, val values: List<Pair<Instant, Double>>)

/** Reads `disks-<bucket>.csv` and turns it into chart lines */
object DiskHistory {
    /** Rows of epoch,mount,used,total; bad rows are skipped */
    fun parse(text: String): List<DiskHistoryPoint> =
        text.lineSequence().mapNotNull { line ->
            val fields = line.split(",")
            if (fields.size != 4 || fields[1].isEmpty()) return@mapNotNull null
            val epoch = fields[0].toDoubleOrNull() ?: return@mapNotNull null
            val used = fields[2].toLongOrNull() ?: return@mapNotNull null
            val total = fields[3].toLongOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
            DiskHistoryPoint(Instant.ofEpochMilli((epoch * 1000).toLong()), fields[1], used, total)
        }.sortedBy { it.date }.toList()

    /** Mounts in the order the chart lists them, root first */
    fun mounts(points: List<DiskHistoryPoint>): List<String> =
        points.map { it.mount }.distinct().sortedWith(compareBy<String> { it != "/" }.thenBy { it })

    fun lines(points: List<DiskHistoryPoint>, choice: DiskChoice): List<DiskLine> = when (choice) {
        is DiskChoice.One -> listOf(DiskLine(choice.mount, values(points.filter { it.mount == choice.mount })))
        DiskChoice.Each -> mounts(points).map { mount -> DiskLine(mount, values(points.filter { it.mount == mount })) }
        DiskChoice.Average -> listOf(
            DiskLine("", points.groupBy { it.date }.map { (date, rows) -> date to rows.sumOf { it.usedPercent } / rows.size }
                .sortedBy { it.first }),
        )
    }

    private fun values(points: List<DiskHistoryPoint>) = points.map { it.date to it.usedPercent }
}

/** Reads the per-filesystem history file over SSH */
class DiskHistoryProbe(private val runner: SSHCommandRunner, private val timeout: Duration = 15.seconds) {
    suspend fun history(bucket: MetricsHistoryBucket, host: SSHHostID): List<DiskHistoryPoint> =
        DiskHistory.parse(runner.run(CommandCatalog.diskHistory(bucket), host, timeout).stdout)
}

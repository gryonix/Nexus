package com.skaymer.gryonixnexus.servercontrol

/** One process as `top` saw it */
data class ProcessSample(
    val pid: Int,
    val user: String,
    val cpu: Double,
    val memoryKiB: Long,
    val command: String,
)

/** A line of the top-processes list */
data class ProcessRow(
    val name: String,
    /** The full command, or empty for a group */
    val detail: String,
    val count: Int,
    val cpu: Double,
    val memoryKiB: Long,
)

/** Reads `top` and names what it lists */
object TopProcesses {
    /** Two samples a second apart: the second is current load */
    const val COMMAND = "LC_ALL=C top -b -n 2 -d 1 -w 512 -c -e k 2>/dev/null"

    fun parse(output: String): List<ProcessSample> {
        val last = output.split("\ntop - ").last()
        var inTable = false
        return last.split("\n").mapNotNull { line ->
            if (line.trim().startsWith("PID ")) {
                inTable = true
                null
            } else if (inTable) sample(line) else null
        }.filter { !it.command.startsWith("top -b -n 2") }
    }

    private fun sample(line: String): ProcessSample? {
        val fields = line.trim().split(Regex(" +"), limit = 12)
        if (fields.size != 12) return null
        val pid = fields[0].toIntOrNull() ?: return null
        val cpu = fields[8].replace(',', '.').toDoubleOrNull() ?: return null
        return ProcessSample(pid, fields[1], cpu, fields[5].toLongOrNull() ?: 0, fields[11])
    }

    /** Named and grouped, or as the system names them */
    fun rows(samples: List<ProcessSample>, friendly: Boolean, byMemory: Boolean, limit: Int = 15): List<ProcessRow> {
        val rows = if (friendly) grouped(samples) else samples.map {
            ProcessRow(executable(it.command), it.command, 1, it.cpu, it.memoryKiB)
        }
        val order = if (byMemory) {
            compareByDescending<ProcessRow> { it.memoryKiB }.thenByDescending { it.cpu }
        } else {
            compareByDescending<ProcessRow> { it.cpu }.thenByDescending { it.memoryKiB }
        }
        return rows.sortedWith(order).take(limit)
    }

    private fun grouped(samples: List<ProcessSample>): List<ProcessRow> =
        samples.groupBy { ProcessNames.friendly(it.command) ?: executable(it.command) }
            .map { (name, members) ->
                ProcessRow(name, "", members.size, members.sumOf { it.cpu }, members.sumOf { it.memoryKiB })
            }

    /** The program's own name, without path or arguments */
    fun executable(command: String): String {
        if (command.startsWith("[")) return command
        val first = command.split(" ").first()
        return first.split("/").last().trim(':')
    }
}

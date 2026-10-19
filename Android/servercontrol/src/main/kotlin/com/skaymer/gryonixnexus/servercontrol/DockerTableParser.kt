package com.skaymer.gryonixnexus.servercontrol

internal object DockerTableParser {
    class Table(val header: String, val rows: List<String>) {
        fun column(name: String, nextColumn: String?): List<String>? {
            val startOffset = header.indexOf(name)
            if (startOffset < 0) return null
            val endOffset = nextColumn?.let { header.indexOf(it) }?.takeIf { it >= 0 }
            return rows.map { row ->
                if (row.length <= startOffset) {
                    ""
                } else {
                    val to = if (endOffset != null && row.length > endOffset) endOffset else row.length
                    row.substring(startOffset, to).trim()
                }
            }
        }
    }

    fun table(output: String, command: String): Table {
        val lines = output.split("\n").filter { it.isNotBlank() }
        // Skip any warning lines docker prints before the actual table.
        val headerIndex = lines.indexOfFirst {
            it.contains("STATUS") && (it.contains("NAME") || it.contains("CONTAINER"))
        }
        if (headerIndex < 0) {
            throw ServerControlError.ParseFailure(command, "no table header in output")
        }
        return Table(lines[headerIndex], lines.drop(headerIndex + 1))
    }
}

/** Parses `docker compose -p <project> ps` into container statuses */
object DockerComposePSParser {
    fun parse(output: String): List<ContainerStatus> {
        val table = DockerTableParser.table(output, "docker compose ps")
        val names = table.column("NAME", "IMAGE")
        val statuses = table.column("STATUS", "PORTS")
        if (names == null || statuses == null) {
            throw ServerControlError.ParseFailure("docker compose ps", "missing NAME/STATUS columns")
        }
        return names.zip(statuses)
            .filter { it.first.isNotEmpty() }
            .map { ContainerStatus(it.first, it.second) }
    }
}

object DockerPSParser {
    fun parse(output: String): List<ContainerStatus> {
        val table = DockerTableParser.table(output, "docker ps -a")
        // NAMES is the last column; STATUS is followed by PORTS.
        val names = table.column("NAMES", null)
        val statuses = table.column("STATUS", "PORTS")
        if (names == null || statuses == null) {
            throw ServerControlError.ParseFailure("docker ps -a", "missing NAMES/STATUS columns")
        }
        return names.zip(statuses)
            .filter { it.first.isNotEmpty() }
            .map { ContainerStatus(it.first, it.second) }
    }

    fun find(container: String, statuses: List<ContainerStatus>): ContainerStatus? =
        statuses.firstOrNull { status ->
            status.name.split(",").map { it.trim() }.contains(container)
        }
}

package com.skaymer.gryonixnexus.servercontrol

/** Parses `systemctl show` blocks into one status per loaded unit */
object SystemdShowParser {
    fun parse(output: String): List<ContainerStatus> =
        output.split("\n\n").mapNotNull { block ->
            val fields = block.split("\n").filter { it.contains('=') }
                .associate { it.substringBefore('=') to it.substringAfter('=') }
            val name = fields["Id"] ?: return@mapNotNull null
            if (fields["LoadState"] == "not-found") return@mapNotNull null
            ContainerStatus(name, status(fields["ActiveState"] ?: ""))
        }

    private fun status(state: String): String = when (state) {
        "active", "reloading" -> "Up (active)"
        "failed" -> "Exited (failed)"
        else -> "not running ($state)"
    }
}

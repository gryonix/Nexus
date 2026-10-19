package com.skaymer.gryonixnexus.catalog

data class PrivilegedCommand(
    /** Absolute binary path as it appears in sudoers, e.g */
    val binaryPath: String,
    /** Verbatim argument string, e.g */
    val arguments: String
) {
    /** The command the app sends over SSH */
    val command: String
        get() {
            val components = binaryPath.split("/").filter { it.isNotEmpty() }
            val directory = components.dropLast(1).joinToString("/")
            val securePath = listOf("usr/local/sbin", "usr/local/bin", "usr/sbin",
                                    "usr/bin", "sbin", "bin")
            val name = if (directory in securePath) {
                components.lastOrNull() ?: binaryPath
            } else {
                binaryPath
            }
            return if (arguments.isEmpty()) "sudo $name" else "sudo $name $arguments"
        }

    fun sudoersLine(user: String): String {
        val target = if (arguments.isEmpty()) binaryPath else "$binaryPath $arguments"
        return "$user ALL=(ALL) NOPASSWD: $target"
    }
}

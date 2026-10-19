package com.skaymer.gryonixnexus.servercontrol

object AccessGrantCommand {
    const val MARKER = "GRYONIXNEXUS_GRANT_OK"

    private const val SH = "$"

    fun command(publicKey: String): String {
        val script = listOf(
            "set -e",
            "k=${ShellQuoting.singleQuoted(publicKey)}",
            "u=$SH{SUDO_USER:-$SH(id -un)}",
            "h=$SH(getent passwd \"${SH}u\" | cut -d: -f6)",
            "[ -n \"${SH}h\" ] || { echo \"no home directory for ${SH}u\" >&2; exit 1; }",
            "mkdir -p \"${SH}h/.ssh\"",
            "chmod 700 \"${SH}h/.ssh\"",
            "touch \"${SH}h/.ssh/authorized_keys\"",
            "chmod 600 \"${SH}h/.ssh/authorized_keys\"",
            "grep -qxF \"${SH}k\" \"${SH}h/.ssh/authorized_keys\" || " +
                "printf \"%s\\n\" \"${SH}k\" >> \"${SH}h/.ssh/authorized_keys\"",
            "if [ \"$SH(id -u)\" = 0 ]; then chown -R \"${SH}u:\" \"${SH}h/.ssh\"; fi",
            "echo \"$MARKER ${SH}u\"",
        ).joinToString("; ")
        return "sh -c ${ShellQuoting.singleQuoted(script)}"
    }
}

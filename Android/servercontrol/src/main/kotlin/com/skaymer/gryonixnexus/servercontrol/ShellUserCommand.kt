package com.skaymer.gryonixnexus.servercontrol

object ShellUserCommand {
    /** Printed on success with the account that now exists */
    const val MARKER = "GRYONIXNEXUS_USER_OK"

    private const val SH = "$"

    /** Names this refuses, and the refusal is the point */
    val RESERVED_NAMES: Set<String> = setOf(
        "root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail",
        "news", "uucp", "proxy", "backup", "list", "irc", "nobody", "systemd",
        "sshd", "docker", "caddy",
    )

    fun isValidName(name: String): Boolean {
        if (name.length !in 1..32) return false
        if (name.lowercase() in RESERVED_NAMES) return false
        val first = name.first()
        if (!(first.isLetter() && first.isLowerCase())) return false
        return name.all { character ->
            (character.isLetter() && character.isLowerCase()) ||
                character.isDigit() ||
                character == '_' || character == '-'
        }
    }

    fun command(name: String, publicKey: String, sudo: Boolean): String? {
        if (!isValidName(name)) return null
        val script = mutableListOf(
            "set -e",
            "u=$name",
            "k=${ShellQuoting.singleQuoted(publicKey)}",
            "id \"${SH}u\" >/dev/null 2>&1 || useradd -m -s /bin/bash \"${SH}u\"",
            "h=$SH(getent passwd \"${SH}u\" | cut -d: -f6)",
            "[ -n \"${SH}h\" ] || { echo \"no home directory for ${SH}u\" >&2; exit 1; }",
            "mkdir -p \"${SH}h/.ssh\"",
            "chmod 700 \"${SH}h/.ssh\"",
            "touch \"${SH}h/.ssh/authorized_keys\"",
            "chmod 600 \"${SH}h/.ssh/authorized_keys\"",
            "grep -qxF \"${SH}k\" \"${SH}h/.ssh/authorized_keys\" || " +
                "printf \"%s\\n\" \"${SH}k\" >> \"${SH}h/.ssh/authorized_keys\"",
            "chown -R \"${SH}u:\" \"${SH}h/.ssh\"",
        )
        if (sudo) {
            script += listOf(
                "t=/etc/sudoers.d/.gryonixnexus-${SH}u.tmp",
                "printf \"%s\\n\" \"${SH}u ALL=(ALL) NOPASSWD:ALL\" > \"${SH}t\"",
                "chmod 440 \"${SH}t\"",
                "visudo -cf \"${SH}t\" >/dev/null",
                "mv \"${SH}t\" /etc/sudoers.d/gryonixnexus-${SH}u",
            )
        }
        script += "echo \"$MARKER ${SH}u\""
        return "sh -c ${ShellQuoting.singleQuoted(script.joinToString("; "))}"
    }
}

package com.skaymer.gryonixnexus.servercontrol

internal object ShellQuoting {
    fun singleQuoted(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"

    /** The value itself when plain, quoted otherwise */
    fun argument(value: String): String {
        val plain = value.isNotEmpty() && value.all {
            (it.code < 128 && it.isLetterOrDigit()) || it in "_@%+=:,./-"
        }
        return if (plain) value else singleQuoted(value)
    }
}

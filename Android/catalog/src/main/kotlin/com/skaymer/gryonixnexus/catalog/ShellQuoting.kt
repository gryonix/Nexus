package com.skaymer.gryonixnexus.catalog

/** Shell single-quoting for values baked into generated setup scripts (e.g */
internal object ShellQuoting {
    fun singleQuoted(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"
}

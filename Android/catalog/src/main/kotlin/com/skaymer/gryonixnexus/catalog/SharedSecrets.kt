package com.skaymer.gryonixnexus.catalog

object SharedSecrets {
    /** Where they live */
    const val DIRECTORY = "/etc/gryonixnexus"

    fun ensureSection(path: String, prefix: String = ""): String = """
        install -d -m 755 '$DIRECTORY'
        if [ ! -s '$path' ]; then
          ( umask 077 && printf '$prefix%s\n' "${SH}(openssl rand -hex 24)" > '$path' )
          chmod 600 '$path'
        fi
        """.trimIndent()
}

package com.skaymer.gryonixnexus.catalog

object Apt {
    const val LOCK_WAIT = "-o DPkg::Lock::Timeout=600"

    /** Keeps edited config files instead of prompting */
    const val KEEP_CONFIGS = "-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

    const val OPTIONS = "$LOCK_WAIT $KEEP_CONFIGS"

    const val QUIET = "DEBIAN_FRONTEND=noninteractive apt-get $OPTIONS"

    /** Caddy's apt repository signs with an expired subkey */
    val RETIRED_SOURCES = listOf(
        "/etc/apt/sources.list.d/caddy-stable.list",
        "/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    )

    /** Drops sources that would fail every apt-get update */
    val DROP_RETIRED_SOURCES = "rm -f " + RETIRED_SOURCES.joinToString(" ")
}

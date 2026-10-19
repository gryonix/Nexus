package com.skaymer.gryonixnexus.app.shell

/** One section of a server's own screen */
enum class ServerSection(val raw: String) {
    GENERAL("general"),
    APPS("operations"),
    METRICS("hosts"),
    CONTAINERS("containers"),
    VPN("vpn"),
    TERMINAL("terminal");

    companion object {
        fun of(raw: String): ServerSection? = entries.firstOrNull { it.raw == raw }
    }
}

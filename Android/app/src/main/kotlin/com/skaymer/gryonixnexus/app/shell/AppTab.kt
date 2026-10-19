package com.skaymer.gryonixnexus.app.shell

enum class AppTab(val key: String) {
    SERVERS("servers"),

    METRICS("metrics"),

    CONTAINERS("containers"),

    VPN("vpn"),

    TERMINAL("terminal"),

    CONFIGURATOR("configurator"),
    SETTINGS("settings");

    val canBeHidden: Boolean get() = this != SETTINGS

    companion object {
        fun of(key: String): AppTab? = entries.firstOrNull { it.key == key }
    }
}

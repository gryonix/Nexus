package com.skaymer.gryonixnexus.app.shell

enum class MetricsPlacement(val raw: String) {
    /** Only the app-wide board */
    DASHBOARD("dashboard"),
    /** Only inside a server, where it has always been */
    SERVER("server"),
    /** Both — the default, and what shipped before this setting existed */
    BOTH("both");

    val showsDashboardTab: Boolean get() = this != SERVER

    val showsInsideServer: Boolean get() = this != DASHBOARD
}

enum class VPNPlacement(val raw: String) {
    TAB("tab"),
    SERVER("server"),
    BOTH("both");

    val showsTab: Boolean get() = this != SERVER
    val showsInsideServer: Boolean get() = this != TAB
}

enum class ContainersPlacement(val raw: String) {
    SECTION("section"),
    /** Inside a server, alongside its metrics — the default */
    SERVER("server"),
    BOTH("both");

    val showsTab: Boolean get() = this != SERVER
    val showsInsideServer: Boolean get() = this != SECTION
}

enum class TerminalPlacement(val raw: String) {
    TAB("tab"),
    /** Inside a server — the default */
    SERVER("server"),
    BOTH("both");

    val showsTab: Boolean get() = this != SERVER
    val showsInsideServer: Boolean get() = this != TAB
}

object DisplaySettings {
    const val METRICS_PLACEMENT_KEY = "metrics.placement"
    const val VPN_PLACEMENT_KEY = "vpn.placement"
    const val CONTAINERS_PLACEMENT_KEY = "containers.placement"
    const val TERMINAL_PLACEMENT_KEY = "terminal.placement"

    fun metrics(raw: String?): MetricsPlacement =
        MetricsPlacement.entries.firstOrNull { it.raw == raw } ?: MetricsPlacement.BOTH

    fun vpn(raw: String?): VPNPlacement =
        VPNPlacement.entries.firstOrNull { it.raw == raw } ?: VPNPlacement.BOTH

    fun containers(raw: String?): ContainersPlacement =
        ContainersPlacement.entries.firstOrNull { it.raw == raw } ?: ContainersPlacement.SERVER

    fun terminal(raw: String?): TerminalPlacement =
        TerminalPlacement.entries.firstOrNull { it.raw == raw } ?: TerminalPlacement.SERVER
}

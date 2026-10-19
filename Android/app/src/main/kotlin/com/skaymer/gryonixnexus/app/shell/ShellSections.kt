package com.skaymer.gryonixnexus.app.shell

/** The sections the shell actually shows, in the user's order */
object ShellSections {
    fun barCapacity(isTablet: Boolean): Int = if (isTablet) Int.MAX_VALUE else 5

    fun visible(
        order: List<AppTab>,
        metricsRaw: String?,
        vpnRaw: String?,
        containersRaw: String?,
        terminalRaw: String?
    ): List<AppTab> {
        val metrics = DisplaySettings.metrics(metricsRaw)
        val vpn = DisplaySettings.vpn(vpnRaw)
        val containers = DisplaySettings.containers(containersRaw)
        val terminal = DisplaySettings.terminal(terminalRaw)
        return order.filter { tab ->
            when (tab) {
                AppTab.METRICS -> metrics.showsDashboardTab
                AppTab.VPN -> vpn.showsTab
                AppTab.CONTAINERS -> containers.showsTab
                AppTab.TERMINAL -> terminal.showsTab
                else -> true
            }
        }
    }

    /** The sections drawn as tabs, and the rest behind More */
    fun onBar(visible: List<AppTab>, capacity: Int): List<AppTab> =
        if (visible.size <= capacity) visible else visible.take(capacity - 1)

    fun behindMore(visible: List<AppTab>, capacity: Int): List<AppTab> =
        if (visible.size <= capacity) emptyList() else visible.drop(capacity - 1)
}

package com.skaymer.gryonixnexus.app.shell

object ShellSectionVisibility {
    fun isOnBar(tab: AppTab, tabs: TabBarSettings, store: SettingsStore): Boolean =
        tabs.isVisible(tab) && placementShowsTab(tab, store)

    /** Put the section on the bar, or take it off */
    fun setOnBar(on: Boolean, tab: AppTab, tabs: TabBarSettings, store: SettingsStore) {
        if (!tab.canBeHidden && !on) return
        val key = placementKey(tab)
        when {
            on -> {
                tabs.setVisible(true, tab)
                if (key != null) store.setString(key, bothValue(tab))
            }
            key != null -> store.setString(key, serverValue(tab))
            else -> tabs.setVisible(false, tab)
        }
    }

    private fun placementShowsTab(tab: AppTab, store: SettingsStore): Boolean = when (tab) {
        AppTab.METRICS ->
            DisplaySettings.metrics(store.string(DisplaySettings.METRICS_PLACEMENT_KEY))
                .showsDashboardTab
        AppTab.VPN ->
            DisplaySettings.vpn(store.string(DisplaySettings.VPN_PLACEMENT_KEY)).showsTab
        AppTab.CONTAINERS ->
            DisplaySettings.containers(store.string(DisplaySettings.CONTAINERS_PLACEMENT_KEY))
                .showsTab
        AppTab.TERMINAL ->
            DisplaySettings.terminal(store.string(DisplaySettings.TERMINAL_PLACEMENT_KEY)).showsTab
        else -> true
    }

    fun placementKey(tab: AppTab): String? = when (tab) {
        AppTab.METRICS -> DisplaySettings.METRICS_PLACEMENT_KEY
        AppTab.VPN -> DisplaySettings.VPN_PLACEMENT_KEY
        AppTab.CONTAINERS -> DisplaySettings.CONTAINERS_PLACEMENT_KEY
        AppTab.TERMINAL -> DisplaySettings.TERMINAL_PLACEMENT_KEY
        else -> null
    }

    private fun bothValue(tab: AppTab): String = when (tab) {
        AppTab.METRICS -> MetricsPlacement.BOTH.raw
        AppTab.VPN -> VPNPlacement.BOTH.raw
        AppTab.CONTAINERS -> ContainersPlacement.BOTH.raw
        AppTab.TERMINAL -> TerminalPlacement.BOTH.raw
        else -> ""
    }

    private fun serverValue(tab: AppTab): String = when (tab) {
        AppTab.METRICS -> MetricsPlacement.SERVER.raw
        AppTab.VPN -> VPNPlacement.SERVER.raw
        AppTab.CONTAINERS -> ContainersPlacement.SERVER.raw
        AppTab.TERMINAL -> TerminalPlacement.SERVER.raw
        else -> ""
    }
}

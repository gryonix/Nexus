package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.app.servers.ServiceGrouping
import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class TabBarSettings(private val store: SettingsStore) {
    object Keys {
        const val ORDER = "tabs.order"
        const val HIDDEN = "tabs.hidden"
        const val START = "tabs.start"
        const val GROUP_SERVICES = ServiceGrouping.OVERRIDE_KEY
        /** The same key the other app writes — see [sitesCollapsible] */
        const val SITES_COLLAPSIBLE = "dashboard.sitesCollapsible"
    }

    private val _order = MutableStateFlow(reconcile(storedOrder(), store))
    val order: StateFlow<List<AppTab>> = _order.asStateFlow()

    private val _hidden = MutableStateFlow(
        (store.stringList(Keys.HIDDEN) ?: emptyList())
            .mapNotNull(AppTab::of)
            .filter { it.canBeHidden }
            .toSet()
    )
    val hidden: StateFlow<Set<AppTab>> = _hidden.asStateFlow()

    private val _startTab = MutableStateFlow(
        store.string(Keys.START)?.let(AppTab::of) ?: AppTab.SERVERS
    )
    val startTab: StateFlow<AppTab> = _startTab.asStateFlow()

    /** Whether the server screen groups its services under category headers */
    private val _groupServices = MutableStateFlow(store.boolean(Keys.GROUP_SERVICES))
    val groupServicesOverride: StateFlow<Boolean?> = _groupServices.asStateFlow()

    /** Whether the sites plate on the server screen folds */
    private val _sitesCollapsible = MutableStateFlow(store.boolean(Keys.SITES_COLLAPSIBLE) ?: true)
    val sitesCollapsible: StateFlow<Boolean> = _sitesCollapsible.asStateFlow()

    fun setSitesCollapsible(value: Boolean) {
        _sitesCollapsible.value = value
        store.setBoolean(Keys.SITES_COLLAPSIBLE, value)
    }

    fun sitesPlateExpanded(folded: Boolean): Boolean = !_sitesCollapsible.value || !folded

    fun setGroupServicesOverride(value: Boolean?) {
        _groupServices.value = value
        if (value == null) store.remove(Keys.GROUP_SERVICES) else store.setBoolean(Keys.GROUP_SERVICES, value)
    }

    fun groupsServices(services: Collection<ServiceID>): Boolean =
        ServiceGrouping.groups(services, _groupServices.value)

    private fun storedOrder(): List<AppTab> =
        (store.stringList(Keys.ORDER) ?: emptyList()).mapNotNull(AppTab::of)

    /** The sections to actually show, in the user's order */
    val visibleTabs: List<AppTab>
        get() {
            val shown = _order.value.filter { it !in _hidden.value }
            return shown.ifEmpty { listOf(AppTab.SETTINGS) }
        }

    val effectiveStartTab: AppTab
        get() = if (visibleTabs.contains(_startTab.value)) _startTab.value
        else visibleTabs.firstOrNull() ?: AppTab.SETTINGS

    fun isVisible(tab: AppTab): Boolean = tab !in _hidden.value

    fun setVisible(visible: Boolean, tab: AppTab) {
        if (!tab.canBeHidden) return
        _hidden.value = if (visible) _hidden.value - tab else _hidden.value + tab
        persistHidden()
    }

    fun setStartTab(tab: AppTab) {
        _startTab.value = tab
        store.setString(Keys.START, tab.key)
    }

    fun moveUp(tab: AppTab) {
        val index = _order.value.indexOf(tab)
        if (index <= 0) return
        reorder(index, index - 1)
    }

    fun moveDown(tab: AppTab) {
        val index = _order.value.indexOf(tab)
        if (index < 0 || index >= _order.value.size - 1) return
        reorder(index, index + 1)
    }

    fun canMoveUp(tab: AppTab): Boolean = _order.value.indexOf(tab) > 0

    fun canMoveDown(tab: AppTab): Boolean {
        val index = _order.value.indexOf(tab)
        return index >= 0 && index < _order.value.size - 1
    }

    private fun reorder(from: Int, to: Int) {
        val next = _order.value.toMutableList()
        next.add(to, next.removeAt(from))
        _order.value = next
        store.setStringList(Keys.ORDER, next.map { it.key })
    }

    private fun persistHidden() {
        store.setStringList(Keys.HIDDEN, _hidden.value.map { it.key }.sorted())
    }

    companion object {
        fun reconcile(stored: List<AppTab>, store: SettingsStore): List<AppTab> {
            val all = AppTab.entries.toList()
            if (stored.isEmpty()) return all
            if (SHIPPED_DEFAULTS.contains(stored)) {
                store.setStringList(Keys.ORDER, all.map { it.key })
                return all
            }
            val result = stored.toMutableList()
            for (tab in all) {
                if (result.contains(tab)) continue
                val canonical = all.indexOf(tab)
                val preceding = all.subList(0, canonical).lastOrNull { result.contains(it) }
                val at = if (preceding == null) 0 else result.indexOf(preceding) + 1
                result.add(at, tab)
            }
            return result
        }

        /** Every order this app has ever shipped as its default */
        private val SHIPPED_DEFAULTS: List<List<AppTab>> = listOf(
            listOf(AppTab.SERVERS, AppTab.METRICS, AppTab.CONFIGURATOR, AppTab.SETTINGS),
            listOf(AppTab.SERVERS, AppTab.METRICS, AppTab.CONFIGURATOR, AppTab.VPN, AppTab.SETTINGS),
            listOf(AppTab.SERVERS, AppTab.METRICS, AppTab.CONFIGURATOR, AppTab.SETTINGS, AppTab.VPN),
            listOf(AppTab.SERVERS, AppTab.METRICS, AppTab.VPN, AppTab.CONFIGURATOR, AppTab.SETTINGS),
            AppTab.entries.toList()
        )
    }
}

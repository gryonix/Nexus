package com.skaymer.gryonixnexus.app.shell

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class ServerSectionSettings(private val store: SettingsStore) {
    object Keys {
        const val ORDER = "server.sectionOrder"
        const val HIDDEN = "server.sectionHidden"
        const val START = "server.sectionStart"
    }

    private val _order = MutableStateFlow(reconcile(store.stringList(Keys.ORDER).orEmpty()))
    val order: StateFlow<List<ServerSection>> = _order.asStateFlow()

    /** Deployment id → the sections that server does not show */
    private val _hidden = MutableStateFlow(readHidden())
    val hidden: StateFlow<Map<String, Set<ServerSection>>> = _hidden.asStateFlow()

    private val _startSection = MutableStateFlow(
        store.string(Keys.START)?.let(ServerSection::of) ?: ServerSection.GENERAL,
    )
    val startSection: StateFlow<ServerSection> = _startSection.asStateFlow()

    /** Is this section shown on this server? */
    fun isVisible(section: ServerSection, deploymentID: String): Boolean =
        _hidden.value[deploymentID]?.contains(section) != true

    /** The sections this server offers, in the person's order */
    fun ordered(available: List<ServerSection>, deploymentID: String): List<ServerSection> =
        _order.value.filter { it in available && isVisible(it, deploymentID) }

    /** The last visible section cannot be hidden */
    fun canHide(section: ServerSection, deploymentID: String, available: List<ServerSection>): Boolean {
        if (!isVisible(section, deploymentID)) return true
        return available.any { it != section && isVisible(it, deploymentID) }
    }

    fun setVisible(
        visible: Boolean,
        section: ServerSection,
        deploymentID: String,
        available: List<ServerSection>,
    ) {
        val current = _hidden.value[deploymentID].orEmpty()
        val updated = when {
            visible -> current - section
            !canHide(section, deploymentID, available) -> return
            else -> current + section
        }
        val map = _hidden.value.toMutableMap()
        if (updated.isEmpty()) map.remove(deploymentID) else map[deploymentID] = updated
        _hidden.value = map
        persistHidden(map)
    }

    fun reachable(current: ServerSection, available: List<ServerSection>, deploymentID: String): ServerSection {
        val shown = ordered(available, deploymentID)
        return if (current in shown) current else shown.firstOrNull() ?: ServerSection.GENERAL
    }

    fun startSection(available: List<ServerSection>, deploymentID: String): ServerSection {
        val shown = ordered(available, deploymentID)
        return if (_startSection.value in shown) _startSection.value else shown.firstOrNull() ?: ServerSection.GENERAL
    }

    fun setStartSection(section: ServerSection) {
        _startSection.value = section
        store.setString(Keys.START, section.raw)
    }

    fun move(section: ServerSection, toIndex: Int) {
        val list = _order.value.toMutableList()
        val from = list.indexOf(section)
        if (from < 0 || toIndex !in list.indices) return
        list.removeAt(from)
        list.add(toIndex, section)
        _order.value = list
        store.setStringList(Keys.ORDER, list.map { it.raw })
    }

    fun forget(deploymentID: String) {
        val map = _hidden.value.toMutableMap()
        if (map.remove(deploymentID) == null) return
        _hidden.value = map
        persistHidden(map)
    }

    private fun readHidden(): Map<String, Set<ServerSection>> =
        store.stringList(Keys.HIDDEN).orEmpty().mapNotNull { row ->
            val index = row.indexOf('=')
            if (index <= 0) return@mapNotNull null
            val sections = row.substring(index + 1).split(',').mapNotNull(ServerSection::of).toSet()
            if (sections.isEmpty()) null else row.substring(0, index) to sections
        }.toMap()

    private fun persistHidden(map: Map<String, Set<ServerSection>>) {
        store.setStringList(
            Keys.HIDDEN,
            map.map { (id, sections) -> "$id=" + sections.joinToString(",") { it.raw } },
        )
    }

    companion object {
        fun available(
            metrics: MetricsPlacement,
            containers: ContainersPlacement,
            vpn: VPNPlacement,
            canListContainers: Boolean,
            hasVPN: Boolean,
        ): List<ServerSection> = buildList {
            add(ServerSection.GENERAL)
            add(ServerSection.APPS)
            if (metrics.showsInsideServer) add(ServerSection.METRICS)
            if (canListContainers && containers.showsInsideServer) add(ServerSection.CONTAINERS)
            if (hasVPN && vpn.showsInsideServer) add(ServerSection.VPN)
            add(ServerSection.TERMINAL)
        }

        fun reconcile(stored: List<String>): List<ServerSection> {
            val known = stored.mapNotNull(ServerSection::of)
            if (known.isEmpty()) return ServerSection.entries.toList()
            val result = known.toMutableList()
            for (section in ServerSection.entries) {
                if (section in result) continue
                val canonical = ServerSection.entries.indexOf(section)
                val preceding = ServerSection.entries.take(canonical).lastOrNull { it in result }
                val at = preceding?.let { result.indexOf(it) + 1 } ?: 0
                result.add(at, section)
            }
            return result
        }
    }
}

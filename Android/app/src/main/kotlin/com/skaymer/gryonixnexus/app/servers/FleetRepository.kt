package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.widgets.WidgetFeed

import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentStore
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import com.skaymer.gryonixnexus.servercontrol.ServerGroups
import com.skaymer.gryonixnexus.servercontrol.remove
import com.skaymer.gryonixnexus.servercontrol.upsert
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class FleetRepository(
    private val store: DeploymentStore,
    private val settings: SettingsStore,
    /** What a removed server takes with it */
    private val eraser: DeploymentEraser,
) {
    private val _deployments = MutableStateFlow<List<Deployment>>(emptyList())
    val deployments: StateFlow<List<Deployment>> = _deployments.asStateFlow()

    private val _groupOrder = MutableStateFlow(ServerGroups.parse(settings.string(ServerGroups.ORDER_KEY)))
    /** The order the strip shows groups in */
    val groupOrder: StateFlow<List<String>> = _groupOrder.asStateFlow()

    /** Whether what is on screen is invented */
    val isDemo: Boolean
        get() = demoCount > 0

    private var storeIsEmpty = false

    /** Unset count means demo while no real server exists */
    private val demoCount: Int
        get() = settings.string(DemoDeployments.COUNT_KEY)?.toIntOrNull()
            ?: if (storeIsEmpty || !LicenseGate.unlocked) DemoDeployments.FULL_COUNT.toInt() else 0

    fun reload() {
        val stored = store.load()
        storeIsEmpty = stored.isEmpty()
        _deployments.value = if (isDemo) DemoDeployments.fleet(demoCount) else stored
    }

    fun add(deployment: Deployment) {
        store.upsert(deployment)
        settings.setString(DemoDeployments.COUNT_KEY, "0")
        reload()
    }

    fun adoptDomain(deployment: Deployment, domain: String) {
        val index = _deployments.value.indexOfFirst { it.id == deployment.id }
        if (index < 0) return
        val current = _deployments.value[index]
        if (current.domain.isNotBlank() || domain.isBlank()) return
        val updated = current.copy(domain = domain.trim().lowercase())
        _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
        if (!isDemo) store.upsert(updated)
    }

    /** Takes the server off the list */
    fun remove(id: String) {
        WidgetFeed.forget(id)
        val deployment = _deployments.value.firstOrNull { it.id == id } ?: return
        _deployments.value = _deployments.value.filterNot { it.id == id }
        if (isDemo) return
        eraser.erase(deployment)
        store.remove(id)
    }

    fun update(deployment: Deployment) {
        val index = _deployments.value.indexOfFirst { it.id == deployment.id }
        if (index < 0) return
        _deployments.value = _deployments.value.toMutableList().also { it[index] = deployment }
        if (!isDemo) store.upsert(deployment)
    }

    /** Adds services another device installed on the server */
    fun addServices(id: String, found: Set<com.skaymer.gryonixnexus.catalog.ServiceID>) {
        val current = _deployments.value.firstOrNull { it.id == id } ?: return
        if (current.services.containsAll(found)) return
        update(current.copy(services = current.services + found))
    }

    /** One server moved in the list */
    fun move(from: Int, to: Int) {
        val reordered = FleetOrder.moved(_deployments.value, from, to)
        if (reordered === _deployments.value) return
        _deployments.value = reordered
        if (!isDemo) store.save(reordered)
    }

    fun setCardSize(id: String, size: ServerCardSize?) {
        val index = _deployments.value.indexOfFirst { it.id == id }
        if (index < 0) return
        val updated = _deployments.value[index].copy(cardSize = size)
        _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
        if (!isDemo) store.upsert(updated)
    }

    /** The load indicator THIS card draws */
    fun setIndicatorStyle(id: String, style: MetricsIndicatorStyle?) {
        val index = _deployments.value.indexOfFirst { it.id == id }
        if (index < 0) return
        val updated = _deployments.value[index].copy(metricsIndicatorStyle = style)
        _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
        if (!isDemo) store.upsert(updated)
    }

    fun setTint(id: String, tintName: String?) {
        val index = _deployments.value.indexOfFirst { it.id == id }
        if (index < 0) return
        val updated = _deployments.value[index].copy(tintName = tintName)
        _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
        if (!isDemo) store.upsert(updated)
    }

    fun setIcon(id: String, iconSymbol: String?) {
        val index = _deployments.value.indexOfFirst { it.id == id }
        if (index < 0) return
        val updated = _deployments.value[index].copy(iconSymbol = iconSymbol)
        _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
        if (!isDemo) store.upsert(updated)
    }

    /** One server joining or leaving a group */
    fun setGroupMember(id: String, group: String, member: Boolean) {
        val index = _deployments.value.indexOfFirst { it.id == id }
        if (index < 0) return
        val current = _deployments.value[index]
        val tags = ServerGroups.setting(member, group, current.tags)
        if (tags == current.tags) return
        val updated = current.copy(tags = tags)
        _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
        if (!isDemo) store.upsert(updated)
    }

    /** The servers in [group] now — everything else loses the tag */
    fun setGroupMembership(group: String, members: Set<String>) {
        for (deployment in _deployments.value.toList()) {
            setGroupMember(deployment.id, group, members.contains(deployment.id))
        }
    }

    /** Moves a group one place left or right */
    fun moveGroup(group: String, offset: Int) {
        val among = ServerGroups.known(_deployments.value)
        ServerGroups.moving(group, offset, among, _groupOrder.value)?.let(::saveOrder)
    }

    /** Groups from an imported file keep their order */
    fun adoptGroupOrder(incoming: List<String>) =
        saveOrder(ServerGroups.adopting(incoming, _groupOrder.value))

    private fun saveOrder(order: List<String>) {
        _groupOrder.value = order
        settings.setString(ServerGroups.ORDER_KEY, ServerGroups.format(order))
    }

    fun renameGroup(from: String, to: String) {
        saveOrder(ServerGroups.renaming(from, to, _groupOrder.value))
        for (deployment in ServerGroups.members(from, _deployments.value)) {
            val index = _deployments.value.indexOfFirst { it.id == deployment.id }
            if (index < 0) continue
            val current = _deployments.value[index]
            val updated = current.copy(
                tags = ServerGroups.setting(
                    true, to, ServerGroups.setting(false, from, current.tags)
                )
            )
            _deployments.value = _deployments.value.toMutableList().also { it[index] = updated }
            if (!isDemo) store.upsert(updated)
        }
    }

    /** Deleting a group deletes no servers */
    fun deleteGroup(group: String) {
        setGroupMembership(group, emptySet())
        saveOrder(ServerGroups.removing(group, _groupOrder.value))
    }
}

package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class MetricPanel(
    val id: String,
    /** Which server */
    val deploymentID: String,
    /** Which machine */
    val hostRaw: String,
    /** One or more metrics, in catalog order */
    val metricsRaw: List<String>,
    val rangeRaw: String,
) {
    val host: SSHHostID
        get() = when {
            hostRaw == HOME_RAW -> SSHHostID.HOME
            hostRaw.startsWith(NODE_PREFIX) -> SSHHostID.node(hostRaw.removePrefix(NODE_PREFIX))
            else -> SSHHostID.VPS
        }

    val metrics: List<HistoryMetric>
        get() = metricsRaw.mapNotNull { raw -> HistoryMetric.entries.firstOrNull { it.key == raw } }
            .ifEmpty { listOf(HistoryMetric.CPU) }

    val metric: HistoryMetric get() = metrics[0]

    val range: HistoryRange get() = HistoryRange.of(rangeRaw) ?: HistoryRange.HOUR

    /** What actually has to be READ for this panel */
    val source: Source get() = Source(deploymentID, hostRaw, range.bucket)

    data class Source(
        val deploymentID: String,
        val hostRaw: String,
        val bucket: MetricsHistoryBucket,
    ) {
        val host: SSHHostID
            get() = when {
                hostRaw == HOME_RAW -> SSHHostID.HOME
                hostRaw.startsWith(NODE_PREFIX) -> SSHHostID.node(hostRaw.removePrefix(NODE_PREFIX))
                else -> SSHHostID.VPS
            }
    }

    /** One stored line */
    fun encoded(): String =
        listOf(id, deploymentID, hostRaw, metricsRaw.joinToString(","), rangeRaw)
            .joinToString(FIELD)

    companion object {
        const val HOME_RAW = "home"
        const val VPS_RAW = "vps"
        const val NODE_PREFIX = "node:"

        private const val FIELD = "|"

        fun of(
            id: String,
            deployment: Deployment,
            host: SSHHostID,
            metrics: List<HistoryMetric>,
            range: HistoryRange,
        ) = MetricPanel(
            id = id,
            deploymentID = deployment.id,
            hostRaw = raw(host),
            metricsRaw = metrics.map { it.key },
            rangeRaw = range.rawValue,
        )

        fun raw(host: SSHHostID): String = when (val kind = host.kind) {
            is SSHHostID.Kind.Slot ->
                if (kind.slot == DeploymentNode.LegacySlot.HOME) HOME_RAW else VPS_RAW
            is SSHHostID.Kind.Node -> "$NODE_PREFIX${kind.id}"
        }

        /** Reads one stored line back */
        fun decode(line: String): MetricPanel? {
            val fields = line.split(FIELD)
            if (fields.size != 5) return null
            if (fields[0].isEmpty() || fields[1].isEmpty()) return null
            return MetricPanel(
                id = fields[0],
                deploymentID = fields[1],
                hostRaw = fields[2],
                metricsRaw = fields[3].split(",").filter { it.isNotEmpty() },
                rangeRaw = fields[4],
            )
        }
    }
}

class MetricPanelStore(private val settings: SettingsStore) {
    private val _panels = MutableStateFlow(load())
    val panels: StateFlow<List<MetricPanel>> = _panels.asStateFlow()

    fun add(panel: MetricPanel) {
        write(_panels.value + panel)
    }

    fun remove(id: String) {
        write(_panels.value.filterNot { it.id == id })
    }

    fun replace(panel: MetricPanel) {
        val current = _panels.value
        if (current.none { it.id == panel.id }) return
        write(current.map { if (it.id == panel.id) panel else it })
    }

    fun reorder(ordered: List<MetricPanel>) {
        val current = _panels.value
        val ids = ordered.map { it.id }.toSet()
        val slots = current.indices.filter { current[it].id in ids }
        val next = current.toMutableList()
        slots.forEachIndexed { index, slot -> ordered.getOrNull(index)?.let { next[slot] = it } }
        write(next)
    }

    /** Drops panels whose server is gone */
    fun prune(deployments: List<Deployment>) {
        val alive = deployments.map { it.id }.toSet()
        val kept = _panels.value.filter { it.deploymentID in alive }
        if (kept.size != _panels.value.size) write(kept)
    }

    private fun write(panels: List<MetricPanel>) {
        _panels.value = panels
        settings.setStringList(KEY, panels.map { it.encoded() })
    }

    private fun load(): List<MetricPanel> =
        settings.stringList(KEY).orEmpty().mapNotNull { MetricPanel.decode(it) }

    private companion object {
        const val KEY = "metrics.dashboardPanels"
    }
}

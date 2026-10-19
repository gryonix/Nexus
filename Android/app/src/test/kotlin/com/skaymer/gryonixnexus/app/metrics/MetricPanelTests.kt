package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.jupiter.api.Test

class MetricPanelTests {
    /** The store the shell models are written against, in memory */
    private class Memory : SettingsStore {
        val values = mutableMapOf<String, Any>()
        private val _revision = MutableStateFlow(0L)
        override val revision: StateFlow<Long> = _revision

        override fun string(key: String): String? = values[key] as? String
        override fun setString(key: String, value: String) { values[key] = value; _revision.value++ }

        @Suppress("UNCHECKED_CAST")
        override fun stringList(key: String): List<String>? = values[key] as? List<String>
        override fun setStringList(key: String, value: List<String>) {
            values[key] = value; _revision.value++
        }

        override fun boolean(key: String): Boolean? = values[key] as? Boolean
        override fun setBoolean(key: String, value: Boolean) { values[key] = value; _revision.value++ }
        override fun remove(key: String) { values.remove(key); _revision.value++ }
    }

    private fun server(id: String) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
    )

    private fun panel(
        id: String,
        deployment: String = "S-1",
        host: SSHHostID = SSHHostID.VPS,
        metrics: List<HistoryMetric> = listOf(HistoryMetric.CPU),
        range: HistoryRange = HistoryRange.HOUR,
    ) = MetricPanel.of(id, server(deployment), host, metrics, range)

    // ------------------------------------------------------------- The panel

    @Test
    fun `a panel survives being written and read back`() {
        val original = panel(
            "P-1",
            metrics = listOf(HistoryMetric.CPU, HistoryMetric.MEMORY),
            range = HistoryRange.THREE_HOURS,
        )
        val restored = MetricPanel.decode(original.encoded())
        assertEquals(original, restored)
        assertEquals(listOf(HistoryMetric.CPU, HistoryMetric.MEMORY), restored!!.metrics)
        assertEquals(HistoryRange.THREE_HOURS, restored.range)
    }

    @Test
    fun `the two slots are stored under the names the other app uses`() {
        assertEquals("vps", MetricPanel.raw(SSHHostID.VPS))
        assertEquals("home", MetricPanel.raw(SSHHostID.HOME))
        assertEquals(SSHHostID.VPS, panel("P", host = SSHHostID.VPS).host)
        assertEquals(SSHHostID.HOME, panel("P", host = SSHHostID.HOME).host)
    }

    @Test
    fun `a node machine round-trips by its own id`() {
        val node = SSHHostID.node("N-7")
        val stored = panel("P", host = node)
        assertEquals(node, MetricPanel.decode(stored.encoded())!!.host)
        assertEquals(node, stored.source.host)
    }

    @Test
    fun `an unknown metric falls back rather than drawing nothing`() {
        val stored = panel("P").copy(metricsRaw = listOf("plasma"))
        assertEquals(listOf(HistoryMetric.CPU), stored.metrics)
        assertEquals(HistoryMetric.CPU, stored.metric)
    }

    @Test
    fun `an unknown range falls back to the hour`() {
        assertEquals(HistoryRange.HOUR, panel("P").copy(rangeRaw = "1 fortnight").range)
    }

    @Test
    fun `a damaged line is not a panel`() {
        assertNull(MetricPanel.decode(""))
        assertNull(MetricPanel.decode("P-1|S-1|vps"))
        assertNull(MetricPanel.decode("|S-1|vps|cpu|1h"))
        assertNull(MetricPanel.decode("P-1||vps|cpu|1h"))
    }

    @Test
    fun `two tiles of the same machine and period share one read`() {
        val cpu = panel("P-1", metrics = listOf(HistoryMetric.CPU), range = HistoryRange.HOUR)
        val memory = panel("P-2", metrics = listOf(HistoryMetric.MEMORY), range = HistoryRange.HOUR)
        assertEquals(cpu.source, memory.source)
    }

    /** Windows that read different files do not */
    @Test
    fun `tiles on different buckets are different reads`() {
        val hour = panel("P-1", range = HistoryRange.HOUR)
        val week = panel("P-2", range = HistoryRange.WEEK)
        assertTrue(hour.source != week.source)
    }

    /** Same period, different MACHINE, is two reads as well */
    @Test
    fun `tiles on different machines are different reads`() {
        val vps = panel("P-1", host = SSHHostID.VPS)
        val home = panel("P-2", host = SSHHostID.HOME)
        assertTrue(vps.source != home.source)
    }

    @Test
    fun `two windows that share a bucket share a read`() {
        val ten = panel("P-1", range = HistoryRange.TEN_MINUTES)
        val thirty = panel("P-2", range = HistoryRange.THIRTY_MINUTES)
        assertEquals(ten.source, thirty.source)
    }

    // ------------------------------------------------------------- The store

    @Test
    fun `the board is what a fresh store reads back`() {
        val settings = Memory()
        val store = MetricPanelStore(settings)
        store.add(panel("P-1"))
        store.add(panel("P-2", metrics = listOf(HistoryMetric.LOAD)))

        val reopened = MetricPanelStore(settings)
        assertEquals(listOf("P-1", "P-2"), reopened.panels.value.map { it.id })
        assertEquals(HistoryMetric.LOAD, reopened.panels.value[1].metric)
    }

    @Test
    fun `removing takes the tile off the board and off the disk`() {
        val settings = Memory()
        val store = MetricPanelStore(settings)
        store.add(panel("P-1"))
        store.add(panel("P-2"))
        store.remove("P-1")

        assertEquals(listOf("P-2"), store.panels.value.map { it.id })
        assertEquals(listOf("P-2"), MetricPanelStore(settings).panels.value.map { it.id })
    }

    @Test
    fun `replacing keeps the tile in its slot`() {
        val store = MetricPanelStore(Memory())
        store.add(panel("P-1"))
        store.add(panel("P-2"))
        store.replace(panel("P-1", metrics = listOf(HistoryMetric.TEMPERATURE)))

        assertEquals(listOf("P-1", "P-2"), store.panels.value.map { it.id })
        assertEquals(HistoryMetric.TEMPERATURE, store.panels.value[0].metric)
    }

    @Test
    fun `replacing a tile the board does not have changes nothing`() {
        val store = MetricPanelStore(Memory())
        store.add(panel("P-1"))
        store.replace(panel("P-9"))
        assertEquals(listOf("P-1"), store.panels.value.map { it.id })
    }

    @Test
    fun `reordering a subset permutes only its own slots`() {
        val store = MetricPanelStore(Memory())
        store.add(panel("A-1", deployment = "S-1"))
        store.add(panel("B-1", deployment = "S-2"))
        store.add(panel("A-2", deployment = "S-1"))

        val mine = store.panels.value.filter { it.deploymentID == "S-1" }
        store.reorder(mine.reversed())

        assertEquals(listOf("A-2", "B-1", "A-1"), store.panels.value.map { it.id })
    }

    @Test
    fun `an order that is not the board's own panels is refused`() {
        val store = MetricPanelStore(Memory())
        store.add(panel("P-1"))
        store.add(panel("P-2"))
        store.add(panel("P-3"))

        store.reorder(listOf(panel("P-1"), panel("P-9")))
        assertEquals(listOf("P-1", "P-2", "P-3"), store.panels.value.map { it.id })

        // The same id twice names two slots and fills one.
        store.reorder(listOf(panel("P-1"), panel("P-1")))
        assertEquals(listOf("P-1", "P-2", "P-3"), store.panels.value.map { it.id })
    }

    /**
     * A tile pointing at a deleted server would sit there forever showing
     * "offline", and the card cannot tell that apart from a machine that is
     * merely down.
     */
    @Test
    fun `a tile whose server is gone is pruned`() {
        val settings = Memory()
        val store = MetricPanelStore(settings)
        store.add(panel("P-1", deployment = "S-1"))
        store.add(panel("P-2", deployment = "S-2"))

        store.prune(listOf(server("S-2")))
        assertEquals(listOf("P-2"), store.panels.value.map { it.id })
        assertEquals(listOf("P-2"), MetricPanelStore(settings).panels.value.map { it.id })
    }

    /**
     * Pruning against a fleet that still holds everything writes NOTHING.
     *
     * Counted by writes, not by what is stored: a prune that rewrites the same
     * list leaves the file identical, so only the store's own revision can tell
     * "changed nothing" from "wrote the same thing back". It is called on every
     * appearance of the board, and a write per appearance is a write per tab
     * switch.
     */
    @Test
    fun `pruning a board whose servers all exist leaves it alone`() {
        val settings = Memory()
        val store = MetricPanelStore(settings)
        store.add(panel("P-1", deployment = "S-1"))
        val writes = settings.revision.value

        store.prune(listOf(server("S-1")))
        assertEquals(listOf("P-1"), store.panels.value.map { it.id })
        assertEquals(writes, settings.revision.value, "prune wrote a list it did not change")
    }
}

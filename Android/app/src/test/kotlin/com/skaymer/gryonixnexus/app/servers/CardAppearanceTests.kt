package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentListCodec
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

class CardAppearanceTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
    }

    private fun server(
        id: String = "alpha",
        size: ServerCardSize? = null,
        style: MetricsIndicatorStyle? = null,
        tint: String? = null,
    ) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "$id.test",
        entry = HostEndpoint(host = "203.0.113.1", user = "root"),
        metricsIndicatorStyle = style,
        cardSize = size,
        tintName = tint,
    )

    // ------------------------------------------------------ Own choice first

    @Test
    fun `a server's own indicator wins over the app default`() {
        assertEquals(
            MetricsIndicatorStyle.RINGS,
            ServerCardLayout.indicatorStyle(
                server(style = MetricsIndicatorStyle.RINGS),
                MetricsIndicatorStyle.BARS
            )
        )
    }

    @Test
    fun `a server that never chose follows the app default`() {
        assertEquals(
            MetricsIndicatorStyle.MINIMAL,
            ServerCardLayout.indicatorStyle(server(), MetricsIndicatorStyle.MINIMAL)
        )
    }

    /** The same rule for the size, stated beside it: one question, two pieces. */
    @Test
    fun `a server's own size wins and an unset one follows the default`() {
        assertEquals(
            ServerCardSize.WIDE,
            ServerCardLayout.size(server(size = ServerCardSize.WIDE), ServerCardSize.COMPACT)
        )
        assertEquals(
            ServerCardSize.COMPACT,
            ServerCardLayout.size(server(), ServerCardSize.COMPACT)
        )
    }

    // ------------------------------------------------------- The stored words

    @Test
    fun `every style has a stored word and reads back as itself`() {
        for (style in MetricsIndicatorStyle.entries) {
            assertEquals(
                style,
                MetricsDisplaySettings.indicatorStyle(MetricsDisplaySettings.raw(style))
            )
        }
    }

    @Test
    fun `an unreadable setting falls back to bars`() {
        assertEquals(MetricsIndicatorStyle.BARS, MetricsDisplaySettings.indicatorStyle(null))
        assertEquals(MetricsIndicatorStyle.BARS, MetricsDisplaySettings.indicatorStyle("sparkles"))
    }

    @Test
    fun `the setting spells a style the way the deployment file does`() {
        for (style in MetricsIndicatorStyle.entries) {
            val text = DeploymentListCodec.encode(listOf(server(style = style)))
            assertTrue(
                text.contains("\"metricsIndicatorStyle\": \"${MetricsDisplaySettings.raw(style)}\""),
                "the file spells $style differently from the setting:\n$text"
            )
        }
    }

    // -------------------------------------------------------------- The writes

    private fun fleet(vararg servers: Deployment): Pair<FleetRepository, InMemoryDeploymentStore> {
        val store = InMemoryDeploymentStore(servers.toList())
        val repository = FleetRepository(store, InMemorySettingsStore(), eraser())
        repository.reload()
        return repository to store
    }

    @Test
    fun `the indicator a card chose is written down, and clearing it writes the absence`() {
        val (repository, store) = fleet(server())

        repository.setIndicatorStyle("alpha", MetricsIndicatorStyle.RINGS)
        assertEquals(MetricsIndicatorStyle.RINGS, store.load().single().metricsIndicatorStyle)

        repository.setIndicatorStyle("alpha", null)
        assertNull(
            store.load().single().metricsIndicatorStyle,
            "clearing froze a style onto the server instead of giving it back to the setting"
        )
    }

    @Test
    fun `the colour a card chose is written down, and clearing it writes the absence`() {
        val (repository, store) = fleet(server())

        repository.setTint("alpha", ServerTint.TEAL.raw)
        assertEquals("teal", store.load().single().tintName)

        repository.setTint("alpha", null)
        assertNull(store.load().single().tintName)
    }

    @Test
    fun `an appearance edit during a demo run never reaches the store`() {
        val store = InMemoryDeploymentStore(listOf(server()))
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "2")
        val repository = FleetRepository(store, settings, eraser())
        repository.reload()

        val target = repository.deployments.value.first()
        repository.setIndicatorStyle(target.id, MetricsIndicatorStyle.RINGS)
        repository.setTint(target.id, ServerTint.RED.raw)

        val shown = repository.deployments.value.first { it.id == target.id }
        assertEquals(MetricsIndicatorStyle.RINGS, shown.metricsIndicatorStyle,
            "the edit did not reach the screen either")
        assertEquals("red", shown.tintName)
        assertEquals(listOf("alpha"), store.load().map { it.id })
        assertNull(store.load().single().metricsIndicatorStyle)
        assertNull(store.load().single().tintName)
    }
}

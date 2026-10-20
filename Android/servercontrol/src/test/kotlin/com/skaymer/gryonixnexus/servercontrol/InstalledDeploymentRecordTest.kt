package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InstalledDeploymentRecordTest {
    private fun stored() = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.4", user = "server-user"),
        services = setOf(ServiceID.VAULTWARDEN),
        usesAgent = true,
        tags = listOf("prod"),
        iconSymbol = "bolt",
        tintName = "teal",
        cardSize = ServerCardSize.COMPACT,
        metricsIndicatorStyle = MetricsIndicatorStyle.RINGS,
        timeouts = OperationTimeouts(quickSeconds = 42),
        wgInterface = "wg1",
        vpnOnRelay = true,
        wakeOnLANMAC = "00:11:22:33:44:55",
        wakeOnLANBroadcast = "192.0.2.255",
    )

    private fun generated(id: String) = Deployment(
        id = id,
        name = "example.com",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.4", user = "server-user"),
        services = setOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD),
    )

    @Test
    fun `a reinstall keeps the agent the app found`() {
        val existing = stored()
        val record = InstalledDeploymentRecord.merged(generated(existing.id), existing)
        assertTrue(
            record.usesAgent,
            "repairing a server made the app forget the daemon it manages it through",
        )
    }

    @Test
    fun `a reinstall keeps what the form never asked about`() {
        val existing = stored()
        val record = InstalledDeploymentRecord.merged(generated(existing.id), existing)
        assertEquals(listOf("prod"), record.tags)
        assertEquals("bolt", record.iconSymbol)
        assertEquals("teal", record.tintName)
        assertEquals(ServerCardSize.COMPACT, record.cardSize)
        assertEquals(MetricsIndicatorStyle.RINGS, record.metricsIndicatorStyle)
        assertEquals(42, record.timeouts.quickSeconds)
        assertEquals("wg1", record.wgInterface)
        assertEquals(existing.storedNodes, record.storedNodes)
        assertEquals(existing.placement, record.placement)
        assertEquals(true, record.vpnOnRelay, "a reinstall moved the VPN back home while it runs on the relay")
        assertEquals("00:11:22:33:44:55", record.wakeOnLANMAC)
        assertEquals("192.0.2.255", record.wakeOnLANBroadcast)
    }

    @Test
    fun `a reinstall still moves what the form does own`() {
        val existing = stored()
        val record = InstalledDeploymentRecord.merged(
            generated(existing.id).copy(
                name = "example.net",
                domain = "example.net",
                additionalDomains = listOf("alias.example.net"),
                entry = HostEndpoint(host = "203.0.113.9", user = "root"),
                usesPasswordAuth = true,
                scope = DeploymentScope.LOCAL_ONLY,
            ),
            existing,
        )
        assertEquals("example.net", record.domain)
        assertEquals("example.net", record.name)
        assertEquals("203.0.113.9", record.entry.host)
        assertEquals("root", record.entry.user)
        assertEquals(listOf("alias.example.net"), record.additionalDomains)
        assertEquals(setOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD), record.services)
        assertTrue(record.usesPasswordAuth)
        assertEquals(DeploymentScope.LOCAL_ONLY, record.scope)
    }

    @Test
    fun `a first install is stored exactly as generated`() {
        val fresh = generated("S-2")
        assertEquals(fresh, InstalledDeploymentRecord.merged(fresh, null))
    }

    /** A deployment that grew a third machine */
    @Test
    fun `a third machine survives a reinstall`() {
        val existing = stored().let { it.copy(storedNodes = it.nodes) }
        val record = InstalledDeploymentRecord.merged(generated(existing.id), existing)
        assertEquals(existing.storedNodes, record.storedNodes)
        assertEquals(existing.nodes.size, record.nodes.size)
    }
}

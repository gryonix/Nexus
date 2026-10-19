package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.core.DNSRecord
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ConfigurationExportPreviewTests {
    private fun form(
        domain: String = "example.com",
        publicIP: String = "203.0.113.10",
    ) = ConfiguratorForm(domain = domain, publicIP = publicIP)

    @Test
    fun `an incomplete form yields no zones`() {
        assertTrue(ConfigurationExport.preview(ConfiguratorForm()).isEmpty())
    }

    @Test
    fun `a filled-in form yields the zone and its records`() {
        val zones = ConfigurationExport.preview(form())
        assertEquals(listOf("example.com"), zones.map { it.domain })
        assertTrue(zones.single().records.isNotEmpty())
        assertTrue(zones.single().copyText.isNotEmpty())
    }

    /** Local-only publishes no address records — there is nothing to preview */
    @Test
    fun `a local-only form has no records to publish`() {
        val local = form(domain = "orion.local", publicIP = "orion.local")
            .copy(scope = DeploymentScope.LOCAL_ONLY)
        assertTrue(ConfigurationExport.preview(local).isEmpty())
    }

    @Test
    fun `records carry the same address the copy text does`() {
        val zone = ConfigurationExport.preview(form()).single()
        val addressRecords = zone.records.filter { it.type == DNSRecord.RecordType.A }
        assertTrue(addressRecords.isNotEmpty())
        assertTrue(addressRecords.all { it.value == "203.0.113.10" })
    }
}

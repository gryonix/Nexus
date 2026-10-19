package com.skaymer.gryonixnexus.app.dns

import com.skaymer.gryonixnexus.servercontrol.DKIMRecord
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class DKIMZonesTests {
    @Test
    fun `every domain gets its own zone with its TXT record`() {
        val zones = DKIMZones.zones(listOf(
            DKIMRecord("dkim._domainkey.b.com", "v=DKIM1; p=B"),
            DKIMRecord("dkim._domainkey.a.com", "v=DKIM1; p=A"),
            DKIMRecord("s2._domainkey.a.com", "v=DKIM1; p=A2"),
        ))
        assertEquals(listOf("a.com", "b.com"), zones.map { it.domain })
        assertEquals(2, zones[0].records.size)
        assertEquals("TXT", zones[1].records.single().type.rawValue)
    }
}

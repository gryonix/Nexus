package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.AmneziaWGVPNService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class VPNPortShareTest {
    private fun context(services: Set<ServiceID>) = ServiceContext(
        domain = "example.com",
        sshUser = "admin",
        settings = ServiceSettings(),
        installedServices = services
    )

    @Test
    fun `the port is shared only with both protocols`() {
        assertEquals(51820, VPNPortShare.sharedPort(context(setOf(ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG))))
        assertNull(VPNPortShare.sharedPort(context(setOf(ServiceID.AMNEZIA_WG))))
        assertNull(VPNPortShare.sharedPort(context(setOf(ServiceID.WIREGUARD_VPN))))
        assertEquals(51822, VPNPortShare.clientPort(context(setOf(ServiceID.AMNEZIA_WG))))
    }

    @Test
    fun `the drop-in replaces its own table and moves other flows`() {
        val text = VPNPortShare.dropIn(51821, 51822)
        assertTrue(text.contains("table inet gryonixnexus_vpn_share\ndelete table inet gryonixnexus_vpn_share\n"))
        assertTrue(
            text.contains(
                "udp dport 51821 @th,64,32 != { 0x01000000, 0x02000000, 0x03000000, 0x04000000 } redirect to :51822\n"
            )
        )
        assertTrue(text.endsWith("    }\n}\n"))
    }

    @Test
    fun `the section clears the share when a protocol is missing`() {
        val alone = VPNPortShare.section(context(setOf(ServiceID.AMNEZIA_WG)))
        assertTrue(alone.contains("nft delete table inet gryonixnexus_vpn_share 2>/dev/null || true"))
        val both = context(setOf(ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG))
        assertTrue(VPNPortShare.section(both).contains("redirect to :51822\n    }\n}\nEOF_VPN_SHARE\nnft -f "))
        assertTrue(AmneziaWGVPNService().reportSteps(both).first().contains("vpn.example.com:51820 (UDP)"))
    }
}

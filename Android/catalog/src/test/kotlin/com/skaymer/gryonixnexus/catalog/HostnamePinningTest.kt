package com.skaymer.gryonixnexus.catalog

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class HostnamePinningTest {
    @Test
    fun `an installed sibling keeps the shared name`() {
        val pinned = ServiceDefaultHostnames.pinningSiblings(
            ServiceID.PSONO, ServiceSettings(), setOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD), "example.com")
        assertEquals("vault.example.com", pinned.vaultwardenHostname)
        assertEquals("", pinned.psonoHostname)
        assertEquals("", pinned.nextcloudHostname)
    }

    @Test
    fun `a chosen name and a lone service stay as they are`() {
        val chosen = ServiceSettings(vaultwardenHostname = "pw.example.com")
        assertEquals("pw.example.com", ServiceDefaultHostnames.pinningSiblings(
            ServiceID.PSONO, chosen, setOf(ServiceID.VAULTWARDEN), "example.com").vaultwardenHostname)
        assertEquals(ServiceSettings(), ServiceDefaultHostnames.pinningSiblings(
            ServiceID.JELLYFIN, ServiceSettings(), setOf(ServiceID.VAULTWARDEN), "example.com"))
    }
}

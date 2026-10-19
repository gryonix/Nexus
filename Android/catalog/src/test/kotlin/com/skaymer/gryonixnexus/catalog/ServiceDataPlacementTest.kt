package com.skaymer.gryonixnexus.catalog

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class ServiceDataPlacementTest {
    private val mount = "/srv/gryonixnexus-storage"

    @Test
    fun `a service moves under the array with its own folder name`() {
        val placed = ServiceDataPlacement.place(ServiceSettings(), ServiceID.VAULTWARDEN, "$mount/")
        assertEquals("/srv/gryonixnexus-storage/vaultwarden/data", placed.vaultwardenDataPath)
    }

    @Test
    fun `media follows jellyfin and placing twice changes nothing`() {
        val once = ServiceDataPlacement.place(ServiceSettings(), ServiceID.JELLYFIN, mount)
        assertEquals("/srv/gryonixnexus-storage/media", once.jellyfinMediaPath)
        assertEquals(once, ServiceDataPlacement.place(once, ServiceID.JELLYFIN, mount))
    }

    @Test
    fun `network services stay put`() {
        assertEquals(ServiceSettings(), ServiceDataPlacement.place(ServiceSettings(), ServiceID.ADGUARD_HOME, mount))
        assertFalse(ServiceDataPlacement.keepsData(ServiceID.ADGUARD_HOME))
    }
}

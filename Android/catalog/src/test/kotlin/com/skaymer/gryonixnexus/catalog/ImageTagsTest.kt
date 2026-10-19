package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.ImmichService
import com.skaymer.gryonixnexus.catalog.services.MailuService
import com.skaymer.gryonixnexus.catalog.services.NextcloudService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class ImageTagsTest {
    @Test
    fun `floating images follow a major tag`() {
        assertEquals("nextcloud:35-apache", NextcloudService.IMAGE)
        assertEquals("ghcr.io/immich-app/immich-server:v3", ImmichService.IMAGE)
        assertEquals("ghcr.io/immich-app/immich-machine-learning:v3", ImmichService.MACHINE_LEARNING_IMAGE)
        assertEquals("redis:8-alpine", MailuService.CACHE_IMAGE)
    }
}

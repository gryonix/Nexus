package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.VaultwardenService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ServiceAPIGroupsTest {
    @Test
    fun `the swift groups are the same`() {
        val ids = listOf(
            ServiceID.VAULTWARDEN, ServiceID.MAILCOW, ServiceID.N8N, ServiceID.NEXTCLOUD,
            ServiceID.IMMICH, ServiceID.SEAFILE, ServiceID.OPEN_WEB_UI, ServiceID.LITE_LLM,
        )
        assertEquals(
            listOf("bitwarden-apps", "mail-sync", "webhooks", "nextcloud-apps", "immich-app", "seafile-apps", "api", "api"),
            ids.map { ServiceAPIGroups.groups(it).single().id },
        )
        assertTrue(ServiceAPIGroups.groups(ServiceID.HEADSCALE).isEmpty())
    }

    @Test
    fun `a group is open only when every path is`() {
        val paths = VaultwardenService.BITWARDEN_API_PATHS
        assertEquals(setOf("bitwarden-apps"), ServiceAPIGroups.openGroups(ServiceID.VAULTWARDEN, paths))
        assertEquals(emptySet<String>(), ServiceAPIGroups.openGroups(ServiceID.VAULTWARDEN, paths.dropLast(1)))
    }

    @Test
    fun `closing a group keeps paths it does not know`() {
        val sent = ServiceAPIGroups.paths(ServiceID.IMMICH, emptySet(), listOf("/custom/*", "/api/*"))
        assertEquals(listOf("/custom/*"), sent)
        assertEquals(
            listOf("/custom/*", "/api/*", "/.well-known/immich"),
            ServiceAPIGroups.paths(ServiceID.IMMICH, setOf("immich-app"), sent),
        )
    }
}

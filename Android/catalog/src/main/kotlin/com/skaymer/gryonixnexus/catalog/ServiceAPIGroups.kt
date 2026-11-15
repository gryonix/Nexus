package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.MailcowService
import com.skaymer.gryonixnexus.catalog.services.N8NService
import com.skaymer.gryonixnexus.catalog.services.VaultwardenService

/** Paths of a service's apps, opened together */
data class ServiceAPIGroup(
    val id: String,
    /** English; the app translates it */
    val title: String,
    val detail: String,
    val paths: List<String>,
)

object ServiceAPIGroups {
    /** The API groups one service offers, none for most */
    fun groups(service: ServiceID): List<ServiceAPIGroup> = when (service) {
        ServiceID.VAULTWARDEN -> listOf(
            ServiceAPIGroup("bitwarden-apps", "Bitwarden apps", "Phone, desktop and browser apps sync your passwords.", VaultwardenService.BITWARDEN_API_PATHS),
        )
        ServiceID.MAILCOW -> listOf(
            ServiceAPIGroup("mail-sync", "Mail apps", "Calendars, contacts and ActiveSync in mail apps.", MailcowService.SYNC_PATHS),
        )
        ServiceID.N8N -> listOf(
            ServiceAPIGroup("webhooks", "Webhooks", "Other services start your workflows.", N8NService.WEBHOOK_PATHS),
        )
        else -> appGroups(service)
    }

    private fun appGroups(service: ServiceID): List<ServiceAPIGroup> = when (service) {
        ServiceID.NEXTCLOUD -> listOf(
            ServiceAPIGroup(
                "nextcloud-apps", "Nextcloud apps", "Files, calendars and contacts in the apps. Sign in once over the VPN.",
                listOf("/remote.php/*", "/ocs/*", "/status.php", "/.well-known/caldav", "/.well-known/carddav"),
            ),
        )
        ServiceID.IMMICH -> listOf(
            ServiceAPIGroup("immich-app", "Immich app", "Photo backup from the phone.", listOf("/api/*", "/.well-known/immich")),
        )
        ServiceID.SEAFILE -> listOf(
            ServiceAPIGroup("seafile-apps", "Seafile apps", "Sync clients and the mobile app.", listOf("/api2/*", "/api/v2.1/*", "/seafhttp/*")),
        )
        ServiceID.OPEN_WEB_UI -> listOf(
            ServiceAPIGroup("api", "API", "Programs that call your models with a key.", listOf("/api/*", "/ollama/*")),
        )
        ServiceID.LITE_LLM -> listOf(
            ServiceAPIGroup(
                "api", "API", "Programs that call your models with a key.",
                listOf("/v1/*", "/chat/completions", "/completions", "/embeddings", "/models"),
            ),
        )
        else -> emptyList()
    }

    /** Groups whose every path is open */
    fun openGroups(service: ServiceID, openPaths: List<String>): Set<String> =
        groups(service).filter { openPaths.containsAll(it.paths) }.map { it.id }.toSet()

    /** The paths to send when these groups are open */
    fun paths(service: ServiceID, openGroups: Set<String>, keeping: List<String>): List<String> {
        val known = groups(service).flatMap { it.paths }.toSet()
        val result = keeping.filter { it !in known }.toMutableList()
        for (group in groups(service)) {
            if (group.id in openGroups) result += group.paths.filter { it !in result }
        }
        return result
    }
}

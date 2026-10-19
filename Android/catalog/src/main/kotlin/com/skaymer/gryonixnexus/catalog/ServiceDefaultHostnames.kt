package com.skaymer.gryonixnexus.catalog

object ServiceDefaultHostnames {
    data class Group(val shared: String, val own: Map<ServiceID, String>)

    val groups: List<Group> = listOf(
        Group(
            "vault",
            mapOf(
                ServiceID.VAULTWARDEN to "vaultwarden",
                ServiceID.PSONO to "psono",
                ServiceID.PASSBOLT to "passbolt",
            ),
        ),
        Group(
            "files",
            mapOf(ServiceID.NEXTCLOUD to "nextcloud", ServiceID.SEAFILE to "seafile"),
        ),
        Group(
            "photos",
            mapOf(ServiceID.IMMICH to "immich", ServiceID.PHOTOPRISM to "photoprism"),
        ),
        Group(
            "dns",
            mapOf(ServiceID.ADGUARD_HOME to "adguard", ServiceID.PIHOLE to "pihole"),
        ),
        Group(
            "git",
            mapOf(ServiceID.FORGEJO to "forgejo", ServiceID.GITLAB to "gitlab"),
        ),
        Group(
            "ai",
            mapOf(
                ServiceID.OPEN_WEB_UI to "openwebui",
                ServiceID.ANYTHING_LLM to "anythingllm",
                ServiceID.LITE_LLM to "litellm",
                ServiceID.OPENCLAW to "openclaw",
            ),
        ),
    )

    /** Services that share their plain name with nobody */
    val sole: Map<ServiceID, String> = mapOf(
        ServiceID.JELLYFIN to "media",
        ServiceID.AUTHELIA to "auth",
        ServiceID.HOMEPAGE to "start",
        ServiceID.HEADSCALE to "mesh",
        ServiceID.CRAFTY_CONTROLLER to "mc",
        ServiceID.N8N to "flows",
        ServiceID.HOME_ASSISTANT to "home",
        ServiceID.ZIGBEE2MQTT to "zigbee",
    )

    fun hostname(id: ServiceID, context: ServiceContext): String =
        "${label(id, context.installedServices)}.${context.domain}"

    /** The label alone */
    fun label(id: ServiceID, installed: Set<ServiceID>): String {
        val group = groups.firstOrNull { it.own.containsKey(id) }
            ?: return sole[id] ?: id.rawValue
        val present = group.own.keys.count { it in installed || it == id }
        return if (present <= 1) group.shared else (group.own[id] ?: id.rawValue)
    }

    /** Keeps installed siblings on the names they already answer on */
    fun pinningSiblings(adding: ServiceID, settings: ServiceSettings, installed: Set<ServiceID>, domain: String): ServiceSettings {
        val group = groups.firstOrNull { it.own.containsKey(adding) } ?: return settings
        var pinned = settings
        for (sibling in group.own.keys) {
            if (sibling == adding || sibling !in installed || hostnameOf(sibling, pinned)?.isEmpty() != true) continue
            val before = label(sibling, installed)
            if (before == label(sibling, installed + adding)) continue
            pinned = withHostname(sibling, pinned, "$before.$domain")
        }
        return pinned
    }

    private fun hostnameOf(id: ServiceID, s: ServiceSettings): String? = when (id) {
        ServiceID.VAULTWARDEN -> s.vaultwardenHostname
        ServiceID.PSONO -> s.psonoHostname
        ServiceID.PASSBOLT -> s.passboltHostname
        ServiceID.NEXTCLOUD -> s.nextcloudHostname
        ServiceID.SEAFILE -> s.seafileHostname
        ServiceID.IMMICH -> s.immichHostname
        ServiceID.PHOTOPRISM -> s.photoprismHostname
        ServiceID.ADGUARD_HOME -> s.adguardHostname
        ServiceID.PIHOLE -> s.piholeHostname
        ServiceID.FORGEJO -> s.forgejoHostname
        ServiceID.GITLAB -> s.gitlabHostname
        ServiceID.OPEN_WEB_UI -> s.openWebUIHostname
        ServiceID.ANYTHING_LLM -> s.anythingLLMHostname
        ServiceID.LITE_LLM -> s.liteLLMHostname
        ServiceID.OPENCLAW -> s.openclawHostname
        else -> null
    }

    private fun withHostname(id: ServiceID, s: ServiceSettings, name: String): ServiceSettings = when (id) {
        ServiceID.VAULTWARDEN -> s.copy(vaultwardenHostname = name)
        ServiceID.PSONO -> s.copy(psonoHostname = name)
        ServiceID.PASSBOLT -> s.copy(passboltHostname = name)
        ServiceID.NEXTCLOUD -> s.copy(nextcloudHostname = name)
        ServiceID.SEAFILE -> s.copy(seafileHostname = name)
        ServiceID.IMMICH -> s.copy(immichHostname = name)
        ServiceID.PHOTOPRISM -> s.copy(photoprismHostname = name)
        ServiceID.ADGUARD_HOME -> s.copy(adguardHostname = name)
        ServiceID.PIHOLE -> s.copy(piholeHostname = name)
        ServiceID.FORGEJO -> s.copy(forgejoHostname = name)
        ServiceID.GITLAB -> s.copy(gitlabHostname = name)
        ServiceID.OPEN_WEB_UI -> s.copy(openWebUIHostname = name)
        ServiceID.ANYTHING_LLM -> s.copy(anythingLLMHostname = name)
        ServiceID.LITE_LLM -> s.copy(liteLLMHostname = name)
        ServiceID.OPENCLAW -> s.copy(openclawHostname = name)
        else -> s
    }
}

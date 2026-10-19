package com.skaymer.gryonixnexus.catalog

object ServiceHostnames {
    /** One settings field, addressable in both directions */
    class Slot(
        val get: (ServiceSettings) -> String,
        val set: (ServiceSettings, String) -> ServiceSettings
    )

    /** The hostname field a service reads, by service id */
    val settings: Map<ServiceID, Slot> = mapOf(
        ServiceID.VAULTWARDEN to Slot({ it.vaultwardenHostname }, { s, v -> s.copy(vaultwardenHostname = v) }),
        ServiceID.PSONO to Slot({ it.psonoHostname }, { s, v -> s.copy(psonoHostname = v) }),
        ServiceID.PASSBOLT to Slot({ it.passboltHostname }, { s, v -> s.copy(passboltHostname = v) }),
        ServiceID.NEXTCLOUD to Slot({ it.nextcloudHostname }, { s, v -> s.copy(nextcloudHostname = v) }),
        ServiceID.SEAFILE to Slot({ it.seafileHostname }, { s, v -> s.copy(seafileHostname = v) }),
        ServiceID.IMMICH to Slot({ it.immichHostname }, { s, v -> s.copy(immichHostname = v) }),
        ServiceID.PHOTOPRISM to Slot({ it.photoprismHostname }, { s, v -> s.copy(photoprismHostname = v) }),
        ServiceID.JELLYFIN to Slot({ it.jellyfinHostname }, { s, v -> s.copy(jellyfinHostname = v) }),
        ServiceID.ADGUARD_HOME to Slot({ it.adguardHostname }, { s, v -> s.copy(adguardHostname = v) }),
        ServiceID.PIHOLE to Slot({ it.piholeHostname }, { s, v -> s.copy(piholeHostname = v) }),
        ServiceID.AUTHELIA to Slot({ it.autheliaHostname }, { s, v -> s.copy(autheliaHostname = v) }),
        ServiceID.HOMEPAGE to Slot({ it.homepageHostname }, { s, v -> s.copy(homepageHostname = v) }),
        ServiceID.HEADSCALE to Slot({ it.headscaleHostname }, { s, v -> s.copy(headscaleHostname = v) }),
        ServiceID.FORGEJO to Slot({ it.forgejoHostname }, { s, v -> s.copy(forgejoHostname = v) }),
        ServiceID.GITLAB to Slot({ it.gitlabHostname }, { s, v -> s.copy(gitlabHostname = v) }),
        ServiceID.CRAFTY_CONTROLLER to Slot({ it.craftyHostname }, { s, v -> s.copy(craftyHostname = v) }),
        ServiceID.OPEN_WEB_UI to Slot({ it.openWebUIHostname }, { s, v -> s.copy(openWebUIHostname = v) }),
        ServiceID.LITE_LLM to Slot({ it.liteLLMHostname }, { s, v -> s.copy(liteLLMHostname = v) }),
        ServiceID.N8N to Slot({ it.n8nHostname }, { s, v -> s.copy(n8nHostname = v) }),
        ServiceID.HOME_ASSISTANT to Slot({ it.homeAssistantHostname }, { s, v -> s.copy(homeAssistantHostname = v) }),
        ServiceID.ZIGBEE2MQTT to Slot({ it.zigbee2MQTTHostname }, { s, v -> s.copy(zigbee2MQTTHostname = v) }),
        ServiceID.ANYTHING_LLM to
            Slot({ it.anythingLLMHostname }, { s, v -> s.copy(anythingLLMHostname = v) }),
        ServiceID.OPENCLAW to
            Slot({ it.openclawHostname }, { s, v -> s.copy(openclawHostname = v) })
    )

    val fixedHostnameServices: Set<ServiceID> = setOf(
        ServiceID.MAILCOW, ServiceID.MAILU, ServiceID.DOCKER_MAILSERVER, ServiceID.VPN_PANEL
    )
}

fun ServiceSettings.applyingHostnames(hostnames: Map<ServiceID, String>): ServiceSettings {
    var settings = this
    for ((id, slot) in ServiceHostnames.settings) {
        settings = slot.set(settings, (hostnames[id] ?: "").trim().lowercase())
    }
    return settings
}

val ServiceSettings.namedHostnames: Map<ServiceID, String>
    get() = ServiceHostnames.settings
        .mapValues { (_, slot) -> slot.get(this) }
        .filterValues { it.isNotEmpty() }

package com.skaymer.gryonixnexus.catalog

/** Service data folders and their move onto an array */
object ServiceDataPlacement {
    /** Services whose data can live on another disk */
    val services: Set<ServiceID> = setOf(
        ServiceID.MAILCOW, ServiceID.MAILU, ServiceID.DOCKER_MAILSERVER, ServiceID.VAULTWARDEN,
        ServiceID.PSONO, ServiceID.PASSBOLT, ServiceID.NEXTCLOUD, ServiceID.SEAFILE, ServiceID.IMMICH,
        ServiceID.PHOTOPRISM, ServiceID.JELLYFIN, ServiceID.FORGEJO, ServiceID.GITLAB,
        ServiceID.MINECRAFT_JAVA, ServiceID.MINECRAFT_BEDROCK, ServiceID.CRAFTY_CONTROLLER,
        ServiceID.OLLAMA, ServiceID.OPEN_WEB_UI, ServiceID.ANYTHING_LLM, ServiceID.QDRANT,
        ServiceID.N8N, ServiceID.HOME_ASSISTANT,
    )

    fun keepsData(id: ServiceID): Boolean = id in services

    /** The same folder name under the mount */
    fun under(mount: String, current: String): String {
        val root = mount.trimEnd('/')
        if (current.startsWith("$root/")) return current
        val parts = current.split('/').filter { it.isNotEmpty() }
        val kept = if (parts.size > 1) parts.drop(1) else parts
        return root + "/" + kept.joinToString("/")
    }

    /** The settings with one service's folders under the mount */
    fun place(settings: ServiceSettings, id: ServiceID, mount: String): ServiceSettings {
        fun at(path: String) = under(mount, path)
        return with(settings) {
            when (id) {
                ServiceID.MAILCOW -> copy(mailcowPath = at(mailcowPath))
                ServiceID.MAILU -> copy(mailuPath = at(mailuPath))
                ServiceID.DOCKER_MAILSERVER -> copy(dockerMailserverPath = at(dockerMailserverPath))
                ServiceID.VAULTWARDEN -> copy(vaultwardenDataPath = at(vaultwardenDataPath))
                ServiceID.PSONO -> copy(psonoPath = at(psonoPath))
                ServiceID.PASSBOLT -> copy(passboltPath = at(passboltPath))
                ServiceID.NEXTCLOUD -> copy(nextcloudPath = at(nextcloudPath))
                ServiceID.SEAFILE -> copy(seafilePath = at(seafilePath))
                ServiceID.IMMICH -> copy(immichPath = at(immichPath))
                ServiceID.PHOTOPRISM -> copy(photoprismPath = at(photoprismPath))
                ServiceID.JELLYFIN -> copy(jellyfinPath = at(jellyfinPath), jellyfinMediaPath = at(jellyfinMediaPath))
                ServiceID.FORGEJO -> copy(forgejoPath = at(forgejoPath))
                ServiceID.GITLAB -> copy(gitlabPath = at(gitlabPath))
                ServiceID.MINECRAFT_JAVA -> copy(minecraftJavaPath = at(minecraftJavaPath))
                ServiceID.MINECRAFT_BEDROCK -> copy(minecraftBedrockPath = at(minecraftBedrockPath))
                ServiceID.CRAFTY_CONTROLLER -> copy(craftyPath = at(craftyPath))
                ServiceID.OLLAMA -> copy(ollamaPath = at(ollamaPath))
                ServiceID.OPEN_WEB_UI -> copy(openWebUIPath = at(openWebUIPath))
                ServiceID.ANYTHING_LLM -> copy(anythingLLMPath = at(anythingLLMPath))
                ServiceID.QDRANT -> copy(qdrantPath = at(qdrantPath))
                ServiceID.N8N -> copy(n8nPath = at(n8nPath))
                ServiceID.HOME_ASSISTANT -> copy(homeAssistantPath = at(homeAssistantPath))
                else -> this
            }
        }
    }
}

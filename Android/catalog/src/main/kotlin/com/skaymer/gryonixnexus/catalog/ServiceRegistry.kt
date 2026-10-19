package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.AdGuardHomeService
import com.skaymer.gryonixnexus.catalog.services.AmneziaWGVPNService
import com.skaymer.gryonixnexus.catalog.services.AutheliaService
import com.skaymer.gryonixnexus.catalog.services.CloudflaredService
import com.skaymer.gryonixnexus.catalog.services.CraftyControllerService
import com.skaymer.gryonixnexus.catalog.services.DockerMailserverService
import com.skaymer.gryonixnexus.catalog.services.ForgejoService
import com.skaymer.gryonixnexus.catalog.services.GitLabService
import com.skaymer.gryonixnexus.catalog.services.HeadscaleService
import com.skaymer.gryonixnexus.catalog.services.HomepageService
import com.skaymer.gryonixnexus.catalog.services.ImmichService
import com.skaymer.gryonixnexus.catalog.services.JellyfinService
import com.skaymer.gryonixnexus.catalog.services.AnythingLLMService
import com.skaymer.gryonixnexus.catalog.services.LiteLLMService
import com.skaymer.gryonixnexus.catalog.services.MailcowService
import com.skaymer.gryonixnexus.catalog.services.MailuService
import com.skaymer.gryonixnexus.catalog.services.MinecraftBedrockService
import com.skaymer.gryonixnexus.catalog.services.MinecraftJavaService
import com.skaymer.gryonixnexus.catalog.services.NextcloudService
import com.skaymer.gryonixnexus.catalog.services.N8NService
import com.skaymer.gryonixnexus.catalog.services.HomeAssistantService
import com.skaymer.gryonixnexus.catalog.services.MosquittoService
import com.skaymer.gryonixnexus.catalog.services.Zigbee2MQTTService
import com.skaymer.gryonixnexus.catalog.services.OllamaService
import com.skaymer.gryonixnexus.catalog.services.OpenClawService
import com.skaymer.gryonixnexus.catalog.services.QdrantService
import com.skaymer.gryonixnexus.catalog.services.SearXNGService
import com.skaymer.gryonixnexus.catalog.services.OpenWebUIService
import com.skaymer.gryonixnexus.catalog.services.OpenVPNService
import com.skaymer.gryonixnexus.catalog.services.PassboltService
import com.skaymer.gryonixnexus.catalog.services.PhotoPrismService
import com.skaymer.gryonixnexus.catalog.services.PiholeService
import com.skaymer.gryonixnexus.catalog.services.PsonoService
import com.skaymer.gryonixnexus.catalog.services.SeafileService
import com.skaymer.gryonixnexus.catalog.services.ShadowsocksService
import com.skaymer.gryonixnexus.catalog.services.TailscaleNodeService
import com.skaymer.gryonixnexus.catalog.services.VPNPanelService
import com.skaymer.gryonixnexus.catalog.services.VaultwardenService
import com.skaymer.gryonixnexus.catalog.services.WireGuardVPNService
import com.skaymer.gryonixnexus.catalog.services.XrayRealityService

/** Catalog of every service gryonixNexus can install and manage */
object ServiceRegistry {
    /** Every service, in the order the catalog presents them */
    val all: List<ManagedService> = listOf(
        MailcowService(),
        MailuService(),
        DockerMailserverService(),
        VaultwardenService(),
        PsonoService(),
        PassboltService(),
        NextcloudService(),
        SeafileService(),
        ImmichService(),
        PhotoPrismService(),
        ForgejoService(),
        GitLabService(),
        JellyfinService(),
        AdGuardHomeService(),
        PiholeService(),
        HeadscaleService(),
        TailscaleNodeService(),
        CloudflaredService(),
        HomepageService(),
        AutheliaService(),
        WireGuardVPNService(),
        AmneziaWGVPNService(),
        ShadowsocksService(),
        XrayRealityService(),
        OpenVPNService(),
        VPNPanelService(),
        MinecraftJavaService(),
        MinecraftBedrockService(),
        CraftyControllerService(),
        OpenWebUIService(),
        OllamaService(),
        AnythingLLMService(),
        LiteLLMService(),
        QdrantService(),
        SearXNGService(),
        OpenClawService(),
        N8NService(),
        HomeAssistantService(),
        MosquittoService(),
        Zigbee2MQTTService()
    )

    /** The members of [category] that this scope can actually run */
    fun services(category: ServiceCategory, scope: DeploymentScope): List<ManagedService> =
        services(category).filter { scope.carriesNonWebServices || !it.requiresPublicDomain }

    /** The same, minus add-ons whose hub is unticked */
    fun services(
        category: ServiceCategory,
        scope: DeploymentScope,
        selected: Set<ServiceID>,
    ): List<ManagedService> =
        services(category, scope).filter {
            it.id !in ServiceID.SMART_HOME_ADD_ONS || ServiceID.HOME_ASSISTANT in selected
        }

    fun expanded(
        selection: Set<ServiceID>,
        scope: DeploymentScope,
        modelBackend: ModelBackend
    ): Set<ServiceID> {
        val ids = selection.toMutableSet()
        if (ids.any { it in ServiceID.VPN_PROTOCOLS }) ids.add(ServiceID.VPN_PANEL)
        if (scope == DeploymentScope.CLOUDFLARE_TUNNEL) ids.add(ServiceID.CLOUDFLARED)
        if (scope.requiresMesh) ids.add(ServiceID.HEADSCALE)
        if (ids.any { it in ServiceID.GAME_SERVERS }) ids.add(ServiceID.CRAFTY_CONTROLLER)
        // Zigbee publishes to the broker, so one brings both
        if (ServiceID.ZIGBEE2MQTT in ids) ids.add(ServiceID.MOSQUITTO)
        if (ids.any { it in ServiceID.MODEL_CONSUMERS } && modelBackend.runsLocalEngine) {
            ids.add(ServiceID.OLLAMA)
        }
        if (ids.any { it in ServiceID.MODEL_CONSUMERS } && modelBackend == ModelBackend.EXTERNAL) {
            ids.add(ServiceID.LITE_LLM)
        }
        if (ServiceID.HEADSCALE in ids) ids.add(ServiceID.TAILSCALE_NODE)
        return ids
    }

    /** The categories that actually have members, in display order */
    val categories: List<ServiceCategory>
        get() {
            val present = all.map { it.category }.toSet()
            return ServiceCategory.SELECTABLE.filter { it in present }.sorted()
        }

    /** Members of a category, in the catalog's stable order */
    fun services(category: ServiceCategory): List<ManagedService> =
        all.filter { it.category == category }

    fun ids(category: ServiceCategory): Set<ServiceID> =
        services(category).map { it.id }.toSet()

    /** What a selection installs from one category, in catalog order */
    fun selection(category: ServiceCategory, from: Set<ServiceID>): List<ServiceID> =
        services(category).map { it.id }.filter { it in from }

    /** Selectable mail engines, in catalog order */
    val mailEngines: List<MailEngineService>
        get() = all.filterIsInstance<MailEngineService>()

    /** Ids of every mail engine */
    val mailEngineIDs: Set<ServiceID>
        get() = mailEngines.map { it.id }.toSet()

    /** The mail engine in a selection, if any */
    fun mailEngine(selection: Set<ServiceID>): ServiceID? =
        mailEngines.firstOrNull { it.id in selection }?.id

    fun service(id: ServiceID): ManagedService? = all.firstOrNull { it.id == id }

    /** Stable order for deterministic script/UI output */
    fun services(ids: Set<ServiceID>): List<ManagedService> = all.filter { it.id in ids }

    /** Conflicting pairs inside a selection (e.g */
    fun conflicts(selection: Set<ServiceID>): List<Pair<ServiceID, ServiceID>> {
        val result = mutableListOf<Pair<ServiceID, ServiceID>>()
        for (service in services(selection)) {
            for (other in service.conflicts.intersect(selection)) {
                if (service.id < other) result.add(service.id to other)
            }
        }
        return result
    }

    /** A relay: WireGuard, firewall, CrowdSec and metrics, no services */
    val relayRequirements = ServerRequirements(memoryMB = 512, diskGB = 2, installsDocker = false)

    /** The minimum server the selected services need */
    fun requirements(selection: Set<ServiceID>): ServerRequirements {
        val baseMemoryMB = 512
        val baseDiskGB = 4
        val selected = services(selection)
        return ServerRequirements(
            memoryMB = baseMemoryMB + selected.sumOf { it.resources.memoryMB },
            diskGB = baseDiskGB + selected.sumOf { it.resources.diskGB },
            installsDocker = needsDocker(selection)
        )
    }

    fun needsDocker(selection: Set<ServiceID>): Boolean =
        services(selection).any { it.runtime is ServiceRuntime.Docker }
}

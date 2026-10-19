package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class CloudflaredService : ManagedService {
    override val id = ServiceID.CLOUDFLARED
    override val displayName = "Cloudflare Tunnel"
    override val systemImage = "cloud"
    override val category = ServiceCategory.REMOTE_ACCESS
    override val usesSharedAdminLogin = false
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** A single Go connector */
    override val resources = ServiceResources(memoryMB = 128, diskGB = 1)

    fun hostname(context: ServiceContext): String = ""

    override fun composeFile(context: ServiceContext) = ComposeFile(
        directory = context.settings.cloudflaredPath,
        composeContents = """
        services:
          cloudflared:
            image: $IMAGE
            container_name: $CONTAINER
            restart: unless-stopped
            # The host's own network, so the tunnel can reach Caddy on
            # 127.0.0.1 exactly as the dashboard's routes name it. A
            # bridge would put the connector on a different loopback and
            # every route would have to name a container address instead.
            network_mode: host
            command: tunnel --no-autoupdate run
            environment:
              # Read from .env, which is 0600 and generated once. The token
              # IS the credential for the whole tunnel.
              TUNNEL_TOKEN: ${SH}{TUNNEL_TOKEN}
        """.trimIndent(),
        envTemplate = """
        TUNNEL_TOKEN=
        """.trimIndent()
    )

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.cloudflaredPath
        val lang = context.language
        return listOf("""
        log "Cloudflare Tunnel: ${L10nServices.serviceStarting(lang)}"
        install -d -m 755 $path
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        # A tunnel without its token retries for ever and says the same
        # thing every time, so the state is named ONCE here instead of
        # being left to be discovered in the container's log.
        if ! grep -q '^TUNNEL_TOKEN=.\+' $path/.env 2>/dev/null; then
          log "${L10nServices.cloudflaredNoTokenNote(lang)}"
        else
          docker compose -p $COMPOSE_PROJECT up -d
        fi
        """.trimIndent())
    }

    /** None, and that is the feature */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.cloudflaredPath
        val lang = context.language
        return listOf("""
        echo "Cloudflare Tunnel:"
        echo "  ${L10nServices.cloudflaredTokenNote(lang)}: $path/.env"
        echo "  ${L10nServices.cloudflaredRoutesNote(lang)}: https://127.0.0.1:443"
        echo "  ${L10nServices.cloudflaredNoPortsNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = CONTAINER,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServicePower.container(CONTAINER, "restart"),
        start = ServicePower.container(CONTAINER, "start"),
        stop = ServicePower.container(CONTAINER, "stop")
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.cloudflaredPath,
        dataPaths = emptyList(),
        backupDirs = emptyList()
    )

    companion object {
        const val COMPOSE_PROJECT = "cloudflared"
        const val CONTAINER = "cloudflared"
        val WRAPPER_TARGET = ServiceID.CLOUDFLARED.rawValue

        /** Exact pinned image tag */
        const val IMAGE = "cloudflare/cloudflared:2026.8.2"
    }
}

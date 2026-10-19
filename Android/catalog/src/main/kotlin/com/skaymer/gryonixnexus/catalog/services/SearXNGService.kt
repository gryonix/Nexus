package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.AIServicesNetwork

import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding
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

class SearXNGService : ManagedService {
    override val id = ServiceID.SEARXNG
    override val displayName = "SearXNG"
    override val systemImage = "magnifyingglass.circle"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 512, diskGB = 1)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.searxngPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              searxng:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  # Signs the form state their pages carry. Generated on the
                  # server; regenerating it on every start would invalidate
                  # every open tab, which is why it lives in `.env`.
                  SEARXNG_SECRET: ${SH}{SEARXNG_SECRET}
                  SEARXNG_PORT: $CONTAINER_PORT
                  # Their default is the rate limiter OFF, and this deployment
                  # is the case it was written for: the port answers on
                  # loopback only, so the callers are the containers on this
                  # host. A limiter here would also need the datastore it
                  # counts in, which is a second container for a queue nobody
                  # outside can join.
                  SEARXNG_LIMITER: "false"
                volumes:
                  # Their entrypoint writes a settings file here when it finds
                  # none. The install below always leaves one, so what runs is
                  # always the file this repository generated.
                  - $path/config:/etc/searxng
                  - $path/cache:/var/cache/searxng
                ports:
                  # Loopback. The neighbours reach it on the shared AI
                  # network; nothing publishes it.
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_PORT"
            """.trimIndent() + AIServicesNetwork.COMPOSE_TAIL,
            envTemplate = """
            SEARXNG_SECRET=__RANDOM__
            """.trimIndent()
        )
    }

    fun settingsFile(context: ServiceContext): String = """
        # Written by gryonixNexus. Upstream's defaults are NOT copied here —
        # they are read out of the image, and only what this deployment
        # changes is named below.
        use_default_settings: true

        search:
          # A program asks for JSON; the default is html only, and a chat that
          # queries this engine gets a refusal without this line.
          formats:
            - html
            - json
        """.trimIndent()

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.searxngPath
        return listOf("""
            log "SearXNG: @STARTING@"
            # Ownership is deliberately not set here: their entrypoint starts
            # as root, chowns both mounts to the container's own user and drops
            # privileges itself. A uid guessed on the host would be a uid to
            # keep in step with their image.
            install -d -m 755 $path $path/config $path/cache
            cat > '${settingsPath(context)}' <<'EOF_SEARXNG_SETTINGS'
            @SETTINGS@
            EOF_SEARXNG_SETTINGS
            chmod 644 '${settingsPath(context)}'
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            ${AIServicesNetwork.CREATE_STEP}
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent().embedding(
                "STARTING" to L10nServices.serviceStarting(context.language),
                "SETTINGS" to settingsFile(context),
            ))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    /** None */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext) = listOf("""
        echo "SearXNG:      127.0.0.1:$WEB_UI_PORT"
        echo "  ${L10nServices.searxngLoopbackNote(context.language)}"
        """.trimIndent())

    override fun actions(context: ServiceContext): ServiceActions = ServiceActions(
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
        configDirectory = context.settings.searxngPath,
        dataPaths = emptyList(),
        backupDirs = emptyList()
    )

    companion object {
        const val COMPOSE_PROJECT = "searxng"
        const val CONTAINER = "searxng"

        /** Next free loopback port in the catalog's block */
        const val WEB_UI_PORT = 8101

        /** The port inside the container */
        const val CONTAINER_PORT = 8080

        val WRAPPER_TARGET = ServiceID.SEARXNG.rawValue

        const val IMAGE = "searxng/searxng:2026.9.7-3e454637f"

        /** The URL a neighbour on this host queries */
        val QUERY_URL = AIServicesNetwork.url(CONTAINER, CONTAINER_PORT) + "/search?q=<query>"

        fun settingsPath(context: ServiceContext): String =
            "${context.settings.searxngPath}/config/settings.yml"
    }
}

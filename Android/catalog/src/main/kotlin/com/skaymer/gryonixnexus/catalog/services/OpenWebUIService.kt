package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.AIServicesNetwork

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupPlan
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.BackupWrapperSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.RestoreSpec
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class OpenWebUIService : ManagedService {
    override val id = ServiceID.OPEN_WEB_UI
    override val displayName = "Open WebUI"
    override val systemImage = "bubble.left.and.text.bubble.right"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 1024, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.openWebUIHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.OPEN_WEB_UI, context)
        } else {
            custom
        }
    }

    fun engineURL(context: ServiceContext): String? {
        if (!context.installedServices.contains(ServiceID.OLLAMA)) return null
        return AIServicesNetwork.url(OllamaService.CONTAINER, OllamaService.API_PORT)
    }

    /** The gateway URL, when this deployment has one */
    fun gatewayURL(context: ServiceContext): String? {
        if (!context.installedServices.contains(ServiceID.LITE_LLM)) return null
        return AIServicesNetwork.url(LiteLLMService.CONTAINER, LiteLLMService.CONTAINER_PORT) + "/v1"
    }

    /** The search engine's query URL, when this deployment installs one */
    fun searchURL(context: ServiceContext): String? {
        if (!context.installedServices.contains(ServiceID.SEARXNG)) return null
        return SearXNGService.QUERY_URL
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.openWebUIPath
        val signups = if (context.settings.openWebUIAllowSignups) "true" else "false"
        val engine = engineURL(context)?.let { "\n      OLLAMA_BASE_URL: \"$it\"" } ?: ""
        val gateway = gatewayURL(context)?.let {
            "\n      OPENAI_API_BASE_URL: \"$it\"\n      OPENAI_API_KEY: ${SH}{LLM_GATEWAY_KEY}"
        } ?: ""
        val search = searchURL(context)?.let {
            "\n      ENABLE_WEB_SEARCH: \"true\"" +
                "\n      WEB_SEARCH_ENGINE: \"searxng\"" +
                "\n      SEARXNG_QUERY_URL: \"$it\""
        } ?: ""
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              open-webui:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  WEBUI_URL: "https://${hostname(context)}"
                  # Session signing key. Generated on the server — regenerating
                  # it on every start would sign every existing session out.
                  WEBUI_SECRET_KEY: ${SH}{WEBUI_SECRET_KEY}
                  ENABLE_SIGNUP: "$signups"@ENGINE@@GATEWAY@@SEARCH@
                volumes:
                  - $path/data:/app/backend/data
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_WEB_PORT"
            """.trimIndent().embedding("ENGINE" to engine, "GATEWAY" to gateway, "SEARCH" to search) +
                AIServicesNetwork.COMPOSE_TAIL,
            envTemplate = "WEBUI_SECRET_KEY=__RANDOM__"
        )
    }

    /** Settings the chat stores and ranks above this environment */
    fun storedAddressKeys(context: ServiceContext): List<String> {
        val keys = mutableListOf<String>()
        if (engineURL(context) != null) keys += "ollama.base_urls"
        if (gatewayURL(context) != null) keys += listOf("openai.api_base_urls", "openai.api_keys")
        if (searchURL(context) != null) {
            keys += listOf("web.search.enable", "web.search.engine", "web.search.searxng_query_url")
        }
        return keys
    }

    /** Drops those settings, so a neighbour added later is seen */
    private fun forgetStoredAddresses(context: ServiceContext, path: String): String {
        val keys = storedAddressKeys(context)
        if (keys.isEmpty()) return ""
        return "\nif [ -f $path/data/webui.db ]; then\n" +
            "  docker run --rm --entrypoint python3 -v $path/data:/data $IMAGE -c '$FORGET_KEYS_SCRIPT' " +
            "/data/webui.db ${keys.joinToString(" ")} || true\nfi"
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.openWebUIPath
        val gateway = if (gatewayURL(context) == null) {
            ""
        } else {
            "\n" + LiteLLMService.appKeySection(ServiceID.OPEN_WEB_UI) + "\n" +
                LiteLLMService.setEnvSection(
                    "$path/.env", "LLM_GATEWAY_KEY",
                    "${SH}(cat '${LiteLLMService.appKeyPath(ServiceID.OPEN_WEB_UI)}')",
                )
        }
        return listOf("""
        log "Open WebUI: ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path/data@GATEWAY@
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q@FORGET@
        ${AIServicesNetwork.CREATE_STEP}
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent().embedding("GATEWAY" to gateway, "FORGET" to forgetStoredAddresses(context, path)))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val lines = mutableListOf(
            """echo "Open WebUI:   https://${hostname(context)}"""",
            """echo "  ${L10nServices.openWebUIAdminWarning(lang)}""""
        )
        if (engineURL(context) == null && gatewayURL(context) == null) {
            lines.add("""echo "  ${L10nServices.openWebUINoEngineNote(lang)}"""")
        }
        return listOf(lines.joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.openWebUIPath
        return ServiceActions(
            statusProbe = StatusProbe.Container(
                name = CONTAINER,
                list = PrivilegedCommand("/usr/bin/docker", "ps -a")
            ),
            restart = ServicePower.container(CONTAINER, "restart"),
            start = ServicePower.container(CONTAINER, "start"),
            stop = ServicePower.container(CONTAINER, "stop"),
            backup = BackupSpec.WrapperScript(BackupWrapperSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                run = ServiceCommand(
                    PrivilegedCommand(BackupWrapperSpec.WRAPPER_PATH, ""),
                    ServiceCommand.TimeoutClass.LONG,
                    streamsOutput = true
                ),
                plan = BackupPlan.Archive(ArchiveBackupPlan(
                    composeProject = COMPOSE_PROJECT,
                    dataPath = "$path/data",
                    databases = emptyList(),
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/data")
                ))
            )),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = false,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.openWebUIPath,
        dataPaths = listOf("${context.settings.openWebUIPath}/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "open-webui"
        const val CONTAINER = "open-webui"

        /** Next free loopback port in the catalog's block */
        const val WEB_UI_PORT = 8097

        const val CONTAINER_WEB_PORT = 8080

        val WRAPPER_TARGET = ServiceID.OPEN_WEB_UI.rawValue

        /** Exact pinned tag */
        const val IMAGE = "ghcr.io/open-webui/open-webui:v0.11.3"

        /** Deletes the named settings from the chat's database */
        const val FORGET_KEYS_SCRIPT = "import sqlite3, sys; db = sqlite3.connect(sys.argv[1]); " +
            "db.executemany(\"delete from config where key = ?\", [(k,) for k in sys.argv[2:]]); db.commit()"
    }
}

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
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class OpenClawService : ManagedService {
    override val id = ServiceID.OPENCLAW
    override val displayName = "OpenClaw"
    override val systemImage = "message.and.waveform"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** A Node process holding one session per paired messenger */
    override val resources = ServiceResources(memoryMB = 1024, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.openclawHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.OPENCLAW, context)
        } else {
            custom
        }
    }

    fun modelEndpoint(context: ServiceContext): String? = when {
        context.installedServices.contains(ServiceID.LITE_LLM) ->
            AIServicesNetwork.url(LiteLLMService.CONTAINER, LiteLLMService.CONTAINER_PORT) + "/v1"
        context.installedServices.contains(ServiceID.OLLAMA) ->
            AIServicesNetwork.url(OllamaService.CONTAINER, OllamaService.API_PORT)
        else -> null
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.openclawPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              openclaw:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                # PID 1 that reaps: this process spawns browsers and helpers,
                # and upstream's own compose asks for the same.
                init: true
                # Upstream's own posture, kept rather than trimmed: a service
                # that talks to strangers' messengers has no use for raw
                # sockets or for interface administration inside its namespace.
                cap_drop:
                  - NET_RAW
                  - NET_ADMIN
                security_opt:
                  - no-new-privileges:true
                environment:
                  # Guards the gateway and its web UI. Generated on the server
                  # — see the report for where to read it.
                  OPENCLAW_GATEWAY_TOKEN: ${SH}{OPENCLAW_GATEWAY_TOKEN}
                  OPENCLAW_GATEWAY_PORT: "$GATEWAY_PORT"
                  OPENCLAW_STATE_DIR: /home/node/.openclaw
                  OPENCLAW_CONFIG_DIR: /home/node/.openclaw
                  OPENCLAW_CONFIG_PATH: /home/node/.openclaw/openclaw.json
                  OPENCLAW_WORKSPACE_DIR: /home/node/.openclaw/workspace
                volumes:
                  # One mount, because the workspace above lives inside the
                  # state directory: two mounts of nested paths would be two
                  # things to keep in step for no second lifetime.
                  - $path/state:/home/node/.openclaw
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$GATEWAY_PORT"
                command:
                  - node
                  - dist/index.js
                  - gateway
                  - --bind
                  - lan
                  - --port
                  - "$GATEWAY_PORT"
            """.trimIndent() + AIServicesNetwork.COMPOSE_TAIL,
            envTemplate = """
            OPENCLAW_GATEWAY_TOKEN=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.openclawPath
        return listOf("""
            log "OpenClaw: @STARTING@"
            install -d -m 755 $path
            # The image runs as uid 1000 and does not chown its own mount.
            # 700, not 755: paired messenger sessions live in here.
            install -d -m 700 -o 1000 -g 1000 $path/state
            # Seeded ONCE and never rewritten. The gateway writes its own
            # settings back into this same file — the paired messengers, the
            # model, the channels — so a re-install that rewrote it would
            # undo the pairings a person made by scanning a QR code.
            if [ ! -s '${configPath(context)}' ]; then
              printf '%s\n' '$SEEDED_CONFIG' > '${configPath(context)}'
            fi
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            ${AIServicesNetwork.CREATE_STEP}
            @TRUST@
            # Applied on every run, not only on the one that created it: the
            # container has to write this file back, and a restore can leave
            # it owned by root — the same reason AnythingLLM's settings file
            # is chowned outside its own seeding block.
            chown 1000:1000 '${configPath(context)}'
            chmod 600 '${configPath(context)}'
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent().embedding(
                "STARTING" to L10nServices.serviceStarting(context.language),
                "TRUST" to trustGatewaySection(context),
            ))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT,
                   overwriteForwardedFor = true)

    override fun dnsHostnames(context: ServiceContext) = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val path = context.settings.openclawPath
        val lines = mutableListOf(
            """echo "OpenClaw:     https://${hostname(context)}"""",
            """echo "  ${L10nServices.openclawTokenNote(lang)}: ${SH}(grep '^OPENCLAW_GATEWAY_TOKEN=' $path/.env | cut -d= -f2-)"""",
            """echo "  ${L10nServices.openclawPairingNote(lang)}""""
        )
        val endpoint = modelEndpoint(context)
        if (endpoint != null) {
            lines.add("""echo "  ${L10nServices.openclawModelNote(lang)}: $endpoint"""")
        } else {
            lines.add("""echo "  ${L10nServices.openclawNoModelNote(lang)}"""")
        }
        return listOf(lines.joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.openclawPath
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
                    dataPath = "$path/state",
                    databases = emptyList(),
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/state")
                ))
            )),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = true,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.openclawPath,
        dataPaths = listOf("${context.settings.openclawPath}/state.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "openclaw"
        const val CONTAINER = "openclaw"

        /** Next free loopback port in the catalog's block */
        const val WEB_UI_PORT = 8102

        const val GATEWAY_PORT = 18789

        val WRAPPER_TARGET = ServiceID.OPENCLAW.rawValue

        const val IMAGE = "ghcr.io/openclaw/openclaw:2026.9.2"

        /** Loopback only; each install adds the shared network's gateway */
        const val SEEDED_CONFIG =
            """{"gateway":{"mode":"local","trustedProxies":["127.0.0.1","::1"]}}"""

        /** Where that file lives */
        fun configPath(context: ServiceContext) = "${context.settings.openclawPath}/state/openclaw.json"

        /** Trusts the shared network's gateway, where Caddy arrives from */
        fun trustGatewaySection(context: ServiceContext): String {
            val config = configPath(context)
            return """
            # Only that address: a home client in 192.168 is no proxy.
            gateway=${SH}(docker network inspect ${AIServicesNetwork.NAME} --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 '\.' || true)
            if [ -n "${SH}gateway" ] && jq --arg g "${SH}gateway" '.gateway.trustedProxies = ["127.0.0.1", "::1", ${SH}g]' '$config' > '$config.new'; then
              mv '$config.new' '$config'
            else
              rm -f '$config.new'
            fi
            """.trimIndent()
        }
    }
}

package com.skaymer.gryonixnexus.catalog.services

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

/** The smart-home hub, on the host network, at home only */
class HomeAssistantService : ManagedService {
    override val id = ServiceID.HOME_ASSISTANT
    override val displayName = "Home Assistant"
    override val systemImage = "house"
    override val category = ServiceCategory.SMART_HOME
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)
    override val requiresHomeMachine: Boolean get() = true

    override val resources = ServiceResources(memoryMB = 1024, diskGB = 3)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.homeAssistantHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.HOME_ASSISTANT, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.homeAssistantPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              homeassistant:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                # Discovery (mDNS, SSDP) only works on the home network itself.
                network_mode: host
                # Bluetooth adapter management, through the host's BlueZ.
                cap_add:
                  - NET_ADMIN
                  - NET_RAW
                volumes:
                  - $path/config:/config
                  - /etc/localtime:/etc/localtime:ro
                  # Bluetooth devices, through the host's BlueZ.
                  - /run/dbus:/run/dbus:ro
            """.trimIndent() + deviceLines(context),
            envTemplate = null
        )
    }

    /** A Zigbee or Z-Wave stick, appended after trimIndent */
    private fun deviceLines(context: ServiceContext): String {
        val device = context.settings.homeAssistantUSBDevice.trim()
        if (device.isEmpty()) return ""
        return "\n    devices:\n      - $device:$device"
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.homeAssistantPath
        val config = "$path/config"
        return listOf(listOf(
            "log \"Home Assistant: ${L10nServices.serviceStarting(context.language)}\"",
            "install -d -m 700 $config",
            "install -d -m 755 $config/themes",
            "if [ ! -f $config/configuration.yaml ]; then",
            "  cat > $config/configuration.yaml <<'EOF_HA_CONFIG'",
            INITIAL_CONFIGURATION,
            "EOF_HA_CONFIG",
            "fi",
            "install -d -m 700 $config/.storage",
            "if [ ! -f $config/.storage/http ]; then",
            "  cat > $config/.storage/http <<'EOF_HA_HTTP'",
            INITIAL_HTTP_STORE,
            "EOF_HA_HTTP",
            "  chmod 600 $config/.storage/http",
            "fi",
            "[ -f $config/automations.yaml ] || echo '[]' > $config/automations.yaml",
            "[ -f $config/scenes.yaml ] || echo '[]' > $config/scenes.yaml",
            "[ -f $config/scripts.yaml ] || : > $config/scripts.yaml",
            "cd $path",
            "docker compose -p $COMPOSE_PROJECT pull -q",
            "docker compose -p $COMPOSE_PROJECT up -d"
        ).joinToString("\n"))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf(listOf(
            "echo \"Home Assistant: https://${hostname(context)}\"",
            "echo \"  ${L10nServices.homeAssistantOwnerWarning(lang)}\"",
            "echo \"  ${L10nServices.homeAssistantAppHint(lang)}\""
        ).joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.homeAssistantPath
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
                    dataPath = "$path/config",
                    databases = emptyList(),
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/config")
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
        configDirectory = context.settings.homeAssistantPath,
        dataPaths = listOf("${context.settings.homeAssistantPath}/config.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "home-assistant"
        const val CONTAINER = "homeassistant"
        const val WEB_UI_PORT = 8123
        val WRAPPER_TARGET = ServiceID.HOME_ASSISTANT.rawValue

        const val IMAGE = "homeassistant/home-assistant:2026.9.3"

        /** First-install settings without the web server block */
        val INITIAL_CONFIGURATION = """
            # Loads the default set of integrations.
            default_config:

            frontend:
              themes: !include_dir_merge_named themes

            automation: !include automations.yaml
            script: !include scripts.yaml
            scene: !include scenes.yaml
        """.trimIndent()

        /** Web server settings: only local Caddy may proxy */
        val INITIAL_HTTP_STORE = """
            {
              "version": 2,
              "minor_version": 2,
              "key": "http",
              "data": {
                "stable": {
                  "server_port": 8123,
                  "server_host": [
                    "127.0.0.1"
                  ],
                  "use_x_forwarded_for": true,
                  "trusted_proxies": [
                    "127.0.0.1/32"
                  ],
                  "cors_allowed_origins": [
                    "https://cast.home-assistant.io"
                  ],
                  "login_attempts_threshold": -1,
                  "ip_ban_enabled": true,
                  "ssl_profile": "modern",
                  "use_x_frame_options": true,
                  "created_at": "2026-09-24T00:00:00+00:00",
                  "error": null,
                  "error_message": null
                },
                "pending": null,
                "yaml_migration_done": true
              }
            }
        """.trimIndent()
    }
}

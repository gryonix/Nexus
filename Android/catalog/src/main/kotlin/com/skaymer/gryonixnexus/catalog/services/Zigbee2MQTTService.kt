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

/** Zigbee devices without a vendor hub of their own */
class Zigbee2MQTTService : ManagedService {
    override val id = ServiceID.ZIGBEE2MQTT
    override val displayName = "Zigbee2MQTT"
    override val systemImage = "antenna.radiowaves.left.and.right"
    override val category = ServiceCategory.SMART_HOME
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)
    override val requiresHomeMachine: Boolean get() = true

    override val resources = ServiceResources(memoryMB = 256, diskGB = 1)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.zigbee2MQTTHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.ZIGBEE2MQTT, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.zigbee2MQTTPath
        val stick = context.settings.homeAssistantUSBDevice
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              zigbee2mqtt:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                volumes:
                  - $path/data:/app/data
                  # Device names as udev knows them.
                  - /run/udev:/run/udev:ro
                devices:
                  - $stick:$stick
                # The broker it publishes to and the page it serves are both
                # on the host's own network; published ports would be ignored.
                network_mode: host
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.zigbee2MQTTPath
        val broker = context.settings.mosquittoPath
        val stick = context.settings.homeAssistantUSBDevice
        val settings = initialConfiguration(stick, "\$MQTT_PASSWORD")
        return listOf(listOf(
            "log \"Zigbee2MQTT: ${L10nServices.serviceStarting(context.language)}\"",
            "install -d -m 755 $path/data",
            ". $broker/.env",
            "if [ ! -f $path/data/configuration.yaml ]; then",
            "  install -m 600 /dev/null $path/data/configuration.yaml",
            "  cat > $path/data/configuration.yaml <<EOF_Z2M_CONFIG",
            settings,
            "EOF_Z2M_CONFIG",
            "fi",
            "cd $path",
            "docker compose -p $COMPOSE_PROJECT pull -q",
            "docker compose -p $COMPOSE_PROJECT up -d",
        ).joinToString("\n"))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> = listOf(listOf(
        "echo \"Zigbee2MQTT:  https://${hostname(context)}\"",
        "echo \"  ${L10nServices.zigbee2MQTTPairingHint(context.language)}\"",
    ).joinToString("\n"))

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.zigbee2MQTTPath
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
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/data")
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
        configDirectory = context.settings.zigbee2MQTTPath,
        dataPaths = listOf("${context.settings.zigbee2MQTTPath}/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "zigbee2mqtt"
        const val CONTAINER = "zigbee2mqtt"
        const val WEB_UI_PORT = 8103
        val WRAPPER_TARGET = ServiceID.ZIGBEE2MQTT.rawValue

        const val IMAGE = "koenkk/zigbee2mqtt:2.14.1"

        /** The broker account this one signs in with */
        const val MQTT_USER = "zigbee2mqtt"

        /** The settings file, written once with the broker's password */
        fun initialConfiguration(stick: String, password: String): String = """
            mqtt:
              server: mqtt://127.0.0.1:${MosquittoService.BROKER_PORT}
              user: $MQTT_USER
              password: $password
            serial:
              port: $stick
            frontend:
              enabled: true
              host: 127.0.0.1
              port: $WEB_UI_PORT
        """.trimIndent()
    }
}

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
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec

/** The MQTT broker the house talks over, at home only */
class MosquittoService : ManagedService {
    override val id = ServiceID.MOSQUITTO
    override val displayName = "Mosquitto"
    override val systemImage = "dot.radiowaves.left.and.right"
    override val category = ServiceCategory.SMART_HOME
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)
    override val requiresHomeMachine: Boolean get() = true

    override val resources = ServiceResources(memoryMB = 128, diskGB = 1)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.mosquittoPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              mosquitto:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                volumes:
                  - $path/config:/mosquitto/config
                  - $path/data:/mosquitto/data
                ports:
                  # The devices in the house speak to it directly.
                  - "$BROKER_PORT:1883"
            """.trimIndent(),
            envTemplate = "MQTT_PASSWORD=__RANDOM__"
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.mosquittoPath
        val config = "$path/config"
        val accounts = USERS.joinToString(" ") { user -> "$user \"\$MQTT_PASSWORD\"" }
        return listOf(listOf(
            "log \"Mosquitto: ${L10nServices.serviceStarting(context.language)}\"",
            "install -d -m 755 $config $path/data",
            "cat > $config/mosquitto.conf <<'EOF_MQTT_CONF'",
            BROKER_CONFIGURATION,
            "EOF_MQTT_CONF",
            ". $path/.env",
            "if [ ! -f $config/passwd ]; then",
            "  install -m 600 /dev/null $config/passwd",
            "  printf '%s:%s\\n' $accounts >> $config/passwd",
            "  docker run --rm -v $config:/mosquitto/config $IMAGE \\",
            "    mosquitto_passwd -U /mosquitto/config/passwd",
            "  docker run --rm -v $config:/mosquitto/config $IMAGE \\",
            "    chown 1883:1883 /mosquitto/config/passwd",
            "fi",
            "cd $path",
            "docker compose -p $COMPOSE_PROJECT pull -q",
            "docker compose -p $COMPOSE_PROJECT up -d",
        ).joinToString("\n"))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> =
        listOf(FirewallPort(BROKER_PORT, FirewallPort.Proto.TCP, "MQTT (home network)"))

    /** None: a broker speaks MQTT, not HTTP */
    override fun webIngress(context: ServiceContext) = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val path = context.settings.mosquittoPath
        return listOf(listOf(
            "echo \"Mosquitto:    ${L10nServices.mosquittoNetworkAddress(lang)}:$BROKER_PORT\"",
            "echo \"  ${L10nServices.mosquittoAccountsLabel(lang)}: ${USERS.joinToString(", ")}\"",
            "echo \"  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: " +
                "\$(grep '^MQTT_PASSWORD=' $path/.env | cut -d= -f2-)\"",
        ).joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.mosquittoPath
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
                    sizePaths = listOf("$path/config", "$path/data")
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
        configDirectory = context.settings.mosquittoPath,
        dataPaths = listOf("${context.settings.mosquittoPath}/config.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "mosquitto"
        const val CONTAINER = "mosquitto"
        const val BROKER_PORT = 1883
        val WRAPPER_TARGET = ServiceID.MOSQUITTO.rawValue

        const val IMAGE = "eclipse-mosquitto:2.0.22"

        /** Both clients this project installs sign in with it */
        val USERS = listOf("homeassistant", "zigbee2mqtt")

        /** Anonymous clients are refused; the password file admits */
        val BROKER_CONFIGURATION = """
            listener 1883
            allow_anonymous false
            password_file /mosquitto/config/passwd
            persistence true
            persistence_location /mosquitto/data/
        """.trimIndent()
    }
}

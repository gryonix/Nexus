package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
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

/** An AirPlay speaker, at home only */
class ShairportSyncService : ManagedService {
    override val id = ServiceID.SHAIRPORT_SYNC
    override val displayName = "AirPlay speaker"
    override val systemImage = "airplayaudio"
    override val category = ServiceCategory.AUDIO
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)
    override val requiresHomeMachine: Boolean get() = true

    override val resources = ServiceResources(memoryMB = 128, diskGB = 1)

    /** The folder the speaker's metadata pipe is shared in */
    private fun metadataMount(context: ServiceContext): String =
        if (ShairportSyncOptions.cecVolume(context).enabled) {
            "\n                  - ${ShairportSyncOptions.CEC_PIPE_DIRECTORY}:${ShairportSyncOptions.CEC_PIPE_DIRECTORY}"
        } else ""

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.shairportPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              shairport-sync:
                image: ${image(context)}
                container_name: $CONTAINER
                restart: unless-stopped
                # Finding the speaker and streaming to it use the host's network.
                network_mode: host
                devices:
                  - /dev/snd
                volumes:
                  - ./$CONFIG_FILE:/etc/shairport-sync.conf:ro${metadataMount(context)}
                command: -a "${speakerName(context)}" -o alsa -- -d ${outputDevice(context)}
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.shairportPath
        return listOf(listOf(
            "log \"AirPlay speaker: ${L10nServices.serviceStarting(context.language)}\"",
            "install -d -m 755 $path",
            "cd $path",
            "cat > $CONFIG_FILE <<'EOF_SHAIRPORT_CONF'",
            ShairportSyncOptions.configContents(context) + "EOF_SHAIRPORT_CONF",
            "docker compose -p $COMPOSE_PROJECT pull -q",
            "docker compose -p $COMPOSE_PROJECT up -d",
        ).joinToString("\n"))
    }

    /** Home network only, never forwarded */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> {
        val tcp = listOf(3689, 5000, 7000).map { FirewallPort(it, FirewallPort.Proto.TCP, "AirPlay (home network)") }
        val udp = (listOf(319, 320, 5353) + (6000..6009))
            .map { FirewallPort(it, FirewallPort.Proto.UDP, "AirPlay (home network)") }
        return tcp + udp
    }

    /** None: a speaker has no web page */
    override fun webIngress(context: ServiceContext) = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf(listOf(
            "echo \"AirPlay:      ${speakerName(context)}\"",
            "echo \"  ${L10nServices.airplaySpeakerHint(lang)}\"",
        ).joinToString("\n"))
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

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(image(context)))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.shairportPath,
        dataPaths = emptyList(),
        backupDirs = emptyList()
    )

    companion object {
        const val COMPOSE_PROJECT = "shairport-sync"
        const val CONTAINER = "shairport-sync"
        const val IMAGE_NAME = "mikebrady/shairport-sync"
        const val DEFAULT_NAME = "gryonix"
        const val DEFAULT_OUTPUT = "default"
        const val AIRPLAY_2 = "airplay2"
        const val AIRPLAY_1 = "airplay1"
        const val CONFIG_FILE = "shairport-sync.conf"
        val WRAPPER_TARGET = ServiceID.SHAIRPORT_SYNC.rawValue

        private const val FORBIDDEN = "\"\\\$`"
        private const val ALLOWED_OUTPUT =
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:,._=-"

        /** "latest" is AirPlay 2, "classic" is AirPlay 1 */
        fun image(context: ServiceContext): String {
            val tag = if (context.settings.shairportMode == AIRPLAY_1) "classic" else "latest"
            return "$IMAGE_NAME:$tag"
        }

        /** The name, safe for a command line */
        fun speakerName(context: ServiceContext): String {
            val kept = context.settings.shairportName
                .filter { it.code >= 0x20 && it.code != 0x7f && it !in FORBIDDEN }
            return kept.trim().ifEmpty { DEFAULT_NAME }
        }

        /** An ALSA device name, plain characters only */
        fun outputDevice(context: ServiceContext): String =
            playable(context.settings.shairportOutput.filter { it in ALLOWED_OUTPUT }.ifEmpty { DEFAULT_OUTPUT })

        /** Pi HDMI cards play only through their hdmi name */
        fun playable(device: String): String =
            if (device.startsWith("hw:CARD=vc4hdmi")) "hdmi:" + device.removePrefix("hw:") else device
    }
}

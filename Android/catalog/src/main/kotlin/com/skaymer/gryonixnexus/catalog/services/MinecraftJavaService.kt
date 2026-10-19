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
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceRecord
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class MinecraftJavaService : ManagedService {
    override val id = ServiceID.MINECRAFT_JAVA
    override val displayName = "Minecraft (Java)"
    override val systemImage = "gamecontroller"
    override val category = ServiceCategory.GAMES
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 3072, diskGB = 8)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val settings = context.settings
        val path = settings.minecraftJavaPath
        val version = settings.minecraftJavaVersion.trim()
        val whitelist = settings.minecraftJavaWhitelist.trim()
        val operators = settings.minecraftJavaOperators.trim()
        val mods = settings.minecraftJavaMods.trim()
        val environment = buildList {
            add("""      EULA: "${if (settings.minecraftJavaAcceptsEULA) "TRUE" else "FALSE"}"""")
            add("""      TYPE: "${settings.minecraftJavaFlavour}"""")
            add("""      MEMORY: "${settings.minecraftJavaMemoryMB}M"""")
            add("      # Enabled so the panel and the backup wrapper can ask a")
            add("      # RUNNING server to flush its world before anything reads it.")
            add("""      ENABLE_RCON: "true"""")
            add("      RCON_PASSWORD: \"${SH}{RCON_PASSWORD}\"")
            if (version.isNotEmpty()) add("""      VERSION: "$version"""")
            if (whitelist.isNotEmpty()) {
                add("""      WHITELIST: "$whitelist"""")
                add("""      ENFORCE_WHITELIST: "true"""")
            }
            if (operators.isNotEmpty()) add("""      OPS: "$operators"""")
            if (mods.isNotEmpty()) {
                add("""      MODRINTH_PROJECTS: "$mods"""")
                add("""      MODRINTH_DOWNLOAD_DEPENDENCIES: "required"""")
            }
        }
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              minecraft-java:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                # The server reads commands from its own stdin, and that is how
                # both a clean stop and the panel's console work. Without these
                # two the container can only be killed, which is how a world
                # gets corrupted.
                stdin_open: true
                tty: true
                environment:
            @ENVIRONMENT@
                volumes:
                  - $path/data:/data
                  # The image's own drop-in directories, and this is where an
                  # uploaded file lands: content here is SYNCHRONISED into
                  # /data/mods (and /data/plugins) at every start, so a jar the
                  # owner sent from the app survives a restart, an image update
                  # and every change to the Modrinth list — which manages only
                  # what it installed itself. Read-only: the server has no
                  # business writing back into what somebody uploaded.
                  #
                  # Both, always, because the answer to "mods or plugins?" is
                  # the TYPE, and the TYPE is a setting that can change on a
                  # server that already exists.
                  - $path/mods:/mods:ro
                  - $path/plugins:/plugins:ro
                ports:
                  - "${settings.minecraftJavaPort}:25565"
                  # RCON stays on loopback: its password is the whole of its
                  # security, and the panel reaches it from the same host.
                  - "127.0.0.1:$RCON_PORT:25575"
            """.trimIndent().embedding("ENVIRONMENT" to environment.joinToString("\n")),
            envTemplate = "RCON_PASSWORD=__RANDOM__"
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.minecraftJavaPath
        return listOf("""
        log "Minecraft (Java): ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path/data $path/mods $path/plugins
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(context.settings.minecraftJavaPort, FirewallPort.Proto.TCP,
                     comment = "Minecraft (Java)")
    )

    /** None */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> =
        listOf("play.${context.domain}")

    override fun serviceRecords(context: ServiceContext) = listOf(
        ServiceRecord(
            name = "_minecraft._tcp.${context.domain}",
            port = context.settings.minecraftJavaPort,
            target = "play.${context.domain}"
        )
    )

    override fun reportSteps(context: ServiceContext): List<String> {
        val settings = context.settings
        val lang = context.language
        val address = if (settings.minecraftJavaPort == 25565) {
            "play.${context.domain}"
        } else {
            "play.${context.domain}:${settings.minecraftJavaPort}"
        }
        val lines = mutableListOf("""
        echo "Minecraft (Java):  $address"
        echo "  ${L10nServices.minecraftFlavourLabel(lang)}: ${settings.minecraftJavaFlavour}"
        """.trimIndent())
        if (!settings.minecraftJavaAcceptsEULA) {
            lines.add("""
            echo "  ${L10nServices.minecraftEULANotAccepted(lang)}"
            """.trimIndent())
        }
        if (settings.minecraftJavaVersion.trim().isEmpty()) {
            lines.add("""
            echo "  ${L10nServices.minecraftVersionFollowsLatest(lang)}"
            """.trimIndent())
        }
        if (settings.minecraftJavaWhitelist.trim().isEmpty()) {
            lines.add("""
            echo "  ${L10nServices.minecraftNoWhitelist(lang)}"
            """.trimIndent())
        }
        val mods = settings.minecraftJavaMods.trim()
        if (mods.isNotEmpty()) {
            lines.add("""
            echo "  ${L10nServices.minecraftModsLabel(lang)}: $mods"
            """.trimIndent())
            if (settings.minecraftJavaFlavour == "VANILLA") {
                lines.add("""
                echo "  ${L10nServices.minecraftModsNeedLoader(lang)}"
                """.trimIndent())
            } else if (settings.minecraftJavaFlavour != "PAPER") {
                lines.add("""
                echo "  ${L10nServices.minecraftModsClientSide(lang)}"
                """.trimIndent())
            }
        }
        return lines
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.minecraftJavaPath
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
        configDirectory = context.settings.minecraftJavaPath,
        dataPaths = listOf("${context.settings.minecraftJavaPath}/data"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "minecraft-java"
        const val CONTAINER = "minecraft-java"
        val WRAPPER_TARGET = ServiceID.MINECRAFT_JAVA.rawValue

        const val IMAGE = "itzg/minecraft-server:2026.8.1-java25"

        /** RCON, on loopback only */
        const val RCON_PORT = 25575
    }
}

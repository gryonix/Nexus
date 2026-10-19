package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.SH
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
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class MinecraftBedrockService : ManagedService {
    override val id = ServiceID.MINECRAFT_BEDROCK
    override val displayName = "Minecraft (Bedrock)"
    override val systemImage = "gamecontroller.fill"
    override val category = ServiceCategory.GAMES
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 1024, diskGB = 4)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val settings = context.settings
        val path = settings.minecraftBedrockPath
        val version = settings.minecraftBedrockVersion.trim()
        val environment = buildList {
            add("""      EULA: "${if (settings.minecraftBedrockAcceptsEULA) "TRUE" else "FALSE"}"""")
            add("""      SERVER_PORT: "${settings.minecraftBedrockPort}"""")
            if (version.isNotEmpty()) add("""      VERSION: "$version"""")
        }
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              minecraft-bedrock:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                # Same reason as the Java server: a clean stop is a command
                # written to the server's stdin, and without a terminal the
                # only way out is a kill.
                stdin_open: true
                tty: true
                environment:
            @ENVIRONMENT@
                volumes:
                  - $path/data:/data
                ports:
                  # UDP, and that is the whole protocol — Bedrock is RakNet
                  # over UDP, so a TCP rule here would open nothing at all.
                  - "${settings.minecraftBedrockPort}:${settings.minecraftBedrockPort}/udp"
            """.trimIndent().embedding("ENVIRONMENT" to environment.joinToString("\n")),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.minecraftBedrockPath
        return listOf("""
        log "Minecraft (Bedrock): ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path/data
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        # The x86 emulator on ARM needs a 4 KB page kernel
        if [ "${SH}(uname -m)" = aarch64 ] && [ "${SH}(getconf PAGESIZE)" != 4096 ]; then
          log "Minecraft (Bedrock): ${L10nServices.minecraftBedrockNeedsSmallPages(context.language)}"
        else
          docker compose -p $COMPOSE_PROJECT up -d
        fi
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(context.settings.minecraftBedrockPort, FirewallPort.Proto.UDP,
                     comment = "Minecraft (Bedrock)")
    )

    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> =
        listOf("play.${context.domain}")

    override fun reportSteps(context: ServiceContext): List<String> {
        val settings = context.settings
        val lang = context.language
        val lines = mutableListOf("""
        echo "Minecraft (Bedrock): play.${context.domain}:${settings.minecraftBedrockPort}"
        echo "  ${L10nServices.minecraftBedrockOnArm(lang)}"
        """.trimIndent())
        if (!settings.minecraftBedrockAcceptsEULA) {
            lines.add("""
            echo "  ${L10nServices.minecraftEULANotAccepted(lang)}"
            """.trimIndent())
        }
        return lines
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.minecraftBedrockPath
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
        configDirectory = context.settings.minecraftBedrockPath,
        dataPaths = listOf("${context.settings.minecraftBedrockPath}/data"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "minecraft-bedrock"
        const val CONTAINER = "minecraft-bedrock"
        val WRAPPER_TARGET = ServiceID.MINECRAFT_BEDROCK.rawValue

        const val IMAGE = "itzg/minecraft-bedrock-server:2026.8.2"
    }
}

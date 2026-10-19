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

class CraftyControllerService : ManagedService {
    override val id = ServiceID.CRAFTY_CONTROLLER
    override val displayName = "Crafty Controller"
    override val systemImage = "slider.horizontal.3"

    override val category = ServiceCategory.IMPLICIT
    /** The games shelf brought it — see `ManagedService.displayCategory` */
    override val displayCategory = ServiceCategory.GAMES
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)
    override val resources = ServiceResources(memoryMB = 512, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.craftyHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.CRAFTY_CONTROLLER, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.craftyPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              crafty:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  TZ: "Etc/UTC"
                volumes:
                  - $path/backups:/crafty/backups
                  - $path/logs:/crafty/logs
                  - $path/servers:/crafty/servers
                  - $path/config:/crafty/app/config
                  - $path/import:/crafty/import
                ports:
                  # Loopback only — Caddy publishes the name, and the panel is
                  # an admin surface like every other one in this catalog.
                  - "127.0.0.1:$WEB_UI_PORT:8443"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.craftyPath
        return listOf("""
        log "Crafty Controller: ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path/backups $path/logs $path/servers $path/config $path/import
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) = WebIngress(
        hostname = hostname(context),
        upstreamPort = WEB_UI_PORT,
        adminGuard = true,
        upstreamHTTPS = true
    )

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf("""
        echo "Crafty Controller: https://${hostname(context)}"
        echo "  ${L10nServices.craftyFirstLogin(lang)}: ${context.settings.craftyPath}/config/default-creds.txt"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.craftyPath
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
                    // SQLite, written while the panel runs.
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/config")
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
        configDirectory = context.settings.craftyPath,
        dataPaths = listOf("${context.settings.craftyPath}/config",
                           "${context.settings.craftyPath}/servers"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "crafty"
        const val CONTAINER = "crafty"
        const val WEB_UI_PORT = 8095
        val WRAPPER_TARGET = ServiceID.CRAFTY_CONTROLLER.rawValue

        /** Pinned release */
        const val IMAGE = "registry.gitlab.com/crafty-controller/crafty-4:4.9.0"
    }
}

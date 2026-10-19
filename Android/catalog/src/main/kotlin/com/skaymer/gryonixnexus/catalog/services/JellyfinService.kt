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

class JellyfinService : ManagedService {
    override val id = ServiceID.JELLYFIN
    override val displayName = "Jellyfin"
    override val systemImage = "play.rectangle"
    override val category = ServiceCategory.MEDIA
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 768, diskGB = 3)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.jellyfinHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.JELLYFIN, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.jellyfinPath
        val media = context.settings.jellyfinMediaPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              jellyfin:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  # Jellyfin builds absolute URLs for clients from this.
                  JELLYFIN_PublishedServerUrl: "https://${hostname(context)}"
                volumes:
                  - $path/config:/config
                  - $path/cache:/cache
                  # Read-only: a media server has no business writing to the
                  # library, and a mistake in the UI would delete originals.
                  - $media:/media:ro
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:8096"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.jellyfinPath
        val media = context.settings.jellyfinMediaPath
        return listOf("""
        log "Jellyfin: ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path/config $path/cache
        # The library directory is created only if it is missing: pointing
        # at an existing library is the normal case, and its ownership and
        # mode are then the user's business, not ours.
        [ -d $media ] || install -d -m 755 $media
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf("""
        echo "Jellyfin:     https://${hostname(context)}"
        echo "  ${L10nServices.jellyfinAdminWarning(lang)}"
        echo "  ${L10nServices.jellyfinLibraryLabel(lang)}: ${context.settings.jellyfinMediaPath}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.jellyfinPath
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
        configDirectory = context.settings.jellyfinPath,
        dataPaths = listOf("${context.settings.jellyfinPath}/config.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "jellyfin"
        const val CONTAINER = "jellyfin"
        const val WEB_UI_PORT = 8096
        val WRAPPER_TARGET = ServiceID.JELLYFIN.rawValue

        const val IMAGE = "jellyfin/jellyfin:10.11.11"
    }
}

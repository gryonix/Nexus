package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupDatabase
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

class ImmichService : ManagedService {
    override val id = ServiceID.IMMICH
    override val displayName = "Immich"
    override val systemImage = "photo.on.rectangle.angled"
    override val category = ServiceCategory.PHOTOS
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 1536, diskGB = 4)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.immichHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.IMMICH, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.immichPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              immich-server:
                image: $IMAGE
                restart: unless-stopped
                depends_on:
                  - redis
                  - database
                environment:
                  DB_HOSTNAME: database
                  DB_USERNAME: postgres
                  DB_PASSWORD: ${SH}{DB_PASSWORD}
                  DB_DATABASE_NAME: immich
                  REDIS_HOSTNAME: redis
                  IMMICH_SERVER_URL: https://${hostname(context)}
                volumes:
                  - $path/library:/usr/src/app/upload
                  - /etc/localtime:/etc/localtime:ro
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:2283"
              immich-machine-learning:
                image: $MACHINE_LEARNING_IMAGE
                restart: unless-stopped
                volumes:
                  - $path/ml-cache:/cache
              redis:
                image: $CACHE_IMAGE
                restart: unless-stopped
              database:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                environment:
                  POSTGRES_PASSWORD: ${SH}{DB_PASSWORD}
                  POSTGRES_USER: postgres
                  POSTGRES_DB: immich
                volumes:
                  - $path/postgres:/var/lib/postgresql/data
            """.trimIndent(),
            envTemplate = """
            DB_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.immichPath
        return listOf("""
        log "Immich: ${L10nServices.serviceStarting(context.language)}"
        install -d $path
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext) = listOf("""
        echo "Immich:       https://${hostname(context)}"
        echo "  ${L10nServices.immichAdminWarning(context.language)}"
        """.trimIndent())

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.immichPath
        return ServiceActions(
            statusProbe = StatusProbe.ComposeProject(
                project = COMPOSE_PROJECT,
                list = PrivilegedCommand("/usr/bin/docker", "compose -p $COMPOSE_PROJECT ps")
            ),
            restart = ServicePower.compose(COMPOSE_PROJECT, "restart"),
            start = ServicePower.compose(COMPOSE_PROJECT, "start"),
            stop = ServicePower.compose(COMPOSE_PROJECT, "stop"),
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
                    dataPath = "$path/library",
                    databases = listOf(BackupDatabase(
                        engine = BackupDatabase.Engine.POSTGRES,
                        service = "database",
                        fileName = "immich.sql"
                    )),
                    quiesceServices = emptyList(),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/library", "$path/postgres")
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

    override fun updateSpec(context: ServiceContext) = UpdateSpec(
        images = listOf(IMAGE, MACHINE_LEARNING_IMAGE, CACHE_IMAGE, DATABASE_IMAGE)
    )

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.immichPath,
        dataPaths = listOf("${context.settings.immichPath}/library.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "immich"
        const val WEB_UI_PORT = 2283

        val WRAPPER_TARGET = ServiceID.IMMICH.rawValue

        const val IMAGE = "ghcr.io/immich-app/immich-server:v3"

        /** Face and object recognition */
        const val MACHINE_LEARNING_IMAGE = "ghcr.io/immich-app/immich-machine-learning:v3"

        /** Redis-compatible cache (valkey), as upstream's own compose file uses */
        const val CACHE_IMAGE = "docker.io/valkey/valkey:8-bookworm"

        const val DATABASE_IMAGE = "ghcr.io/immich-app/postgres:16-vectorchord0.4.3"
    }
}

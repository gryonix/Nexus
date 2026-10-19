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

class PhotoPrismService : ManagedService {
    override val id = ServiceID.PHOTOPRISM
    override val displayName = "PhotoPrism"
    override val systemImage = "photo.stack"
    override val category = ServiceCategory.PHOTOS
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 2048, diskGB = 6)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.photoprismHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.PHOTOPRISM, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.photoprismPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              mariadb:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                command: --transaction-isolation=READ-COMMITTED --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --max-connections=512 --innodb-rollback-on-timeout=OFF --innodb-lock-wait-timeout=120
                environment:
                  MARIADB_AUTO_UPGRADE: "1"
                  MARIADB_INITDB_SKIP_TZINFO: "1"
                  # The MYSQL_* spellings, not upstream's MARIADB_*: the shared
                  # backup wrapper dumps a database by reading
                  # MYSQL_ROOT_PASSWORD and MYSQL_DATABASE out of the
                  # container's OWN environment (a password passed from the
                  # host would sit in the argv of docker exec, readable from
                  # /proc). The image accepts both spellings; only one of them
                  # makes the backup work.
                  MYSQL_DATABASE: photoprism
                  MYSQL_USER: photoprism
                  MYSQL_PASSWORD: ${SH}{MYSQL_PASSWORD}
                  MYSQL_ROOT_PASSWORD: ${SH}{MYSQL_ROOT_PASSWORD}
                volumes:
                  - $path/db:/var/lib/mysql
              photoprism:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                depends_on:
                  - mariadb
                working_dir: "/photoprism"
                environment:
                  PHOTOPRISM_ADMIN_USER: ${context.settings.adminUsername}
                  PHOTOPRISM_ADMIN_PASSWORD: ${SH}{PHOTOPRISM_ADMIN_PASSWORD}
                  # Password auth, never the public mode: this is a public
                  # hostname, and "public" means the library is too.
                  PHOTOPRISM_AUTH_MODE: "password"
                  PHOTOPRISM_SITE_URL: "https://${hostname(context)}/"
                  # Caddy terminates TLS and speaks plain HTTP to this port;
                  # left at its default PhotoPrism would serve its own
                  # self-signed certificate and the proxy would not trust it.
                  PHOTOPRISM_DISABLE_TLS: "true"
                  PHOTOPRISM_DEFAULT_TLS: "false"
                  PHOTOPRISM_DATABASE_DRIVER: "mysql"
                  PHOTOPRISM_DATABASE_SERVER: "mariadb:3306"
                  PHOTOPRISM_DATABASE_NAME: "photoprism"
                  PHOTOPRISM_DATABASE_USER: "photoprism"
                  PHOTOPRISM_DATABASE_PASSWORD: ${SH}{MYSQL_PASSWORD}
                  # Sidecar YAML on: it is what lets the metadata be rebuilt
                  # from the originals alone, and the originals are what the
                  # backup carries.
                  PHOTOPRISM_SIDECAR_YAML: "true"
                  PHOTOPRISM_BACKUP_ALBUMS: "true"
                volumes:
                  - $path/originals:/photoprism/originals
                  - $path/storage:/photoprism/storage
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:2342"
            """.trimIndent(),
            envTemplate = """
            MYSQL_ROOT_PASSWORD=__RANDOM__
            MYSQL_PASSWORD=__RANDOM__
            PHOTOPRISM_ADMIN_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.photoprismPath
        return listOf("""
        log "PhotoPrism: ${L10nServices.serviceStarting(context.language)}"
        # Modes are spelled out rather than left to the umask: PhotoPrism
        # drops to its own user and has to write into both of these.
        install -d -m 755 $path/originals $path/storage
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
        val path = context.settings.photoprismPath
        val lang = context.language
        return listOf("""
        echo "PhotoPrism:   https://${hostname(context)}"
        echo "  ${L10nServices.administratorLabel(lang)}: ${context.settings.adminUsername}"
        echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^PHOTOPRISM_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"
        echo "  ${L10nServices.photoprismOriginalsLabel(lang)}: $path/originals"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.photoprismPath
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
                    dataPath = "$path/originals",
                    databases = listOf(BackupDatabase(
                        engine = BackupDatabase.Engine.MYSQL,
                        service = "mariadb",
                        fileName = "photoprism.sql"
                    )),
                    quiesceServices = emptyList(),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/originals", "$path/storage", "$path/db")
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

    override fun updateSpec(context: ServiceContext) =
        UpdateSpec(images = listOf(IMAGE, DATABASE_IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.photoprismPath,
        dataPaths = listOf("${context.settings.photoprismPath}/originals.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "photoprism"
        const val CONTAINER = "photoprism"

        const val WEB_UI_PORT = 2342
        val WRAPPER_TARGET = ServiceID.PHOTOPRISM.rawValue

        const val IMAGE = "photoprism/photoprism:260728"

        const val DATABASE_IMAGE = "mariadb:11"
    }
}

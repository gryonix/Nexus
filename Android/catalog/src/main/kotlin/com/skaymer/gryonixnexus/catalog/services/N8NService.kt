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

class N8NService : ManagedService {
    override val id = ServiceID.N8N
    override val displayName = "n8n"
    override val systemImage = "arrow.triangle.branch"
    override val category = ServiceCategory.AUTOMATION
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** Node with a PostgreSQL beside it */
    override val resources = ServiceResources(memoryMB = 1024, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.n8nHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.N8N, context)
        } else {
            custom
        }
    }

    fun baseURL(context: ServiceContext): String = "https://${hostname(context)}/"

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.n8nPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              n8n:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                depends_on:
                  - $DATABASE_SERVICE
                environment:
                  DB_TYPE: postgresdb
                  DB_POSTGRESDB_HOST: $DATABASE_SERVICE
                  DB_POSTGRESDB_DATABASE: $DATABASE_NAME
                  DB_POSTGRESDB_USER: $DATABASE_NAME
                  DB_POSTGRESDB_PASSWORD: ${SH}{DB_PASSWORD}
                  # Both halves of "which address is this?": the first is what
                  # n8n checks incoming requests against, the second is what it
                  # PRINTS into every webhook URL and every editor link.
                  N8N_HOST: ${hostname(context)}
                  WEBHOOK_URL: "${baseURL(context)}"
                  N8N_EDITOR_BASE_URL: "${baseURL(context)}"
                  N8N_PROTOCOL: https
                  N8N_PORT: $CONTAINER_PORT
                  # Caddy is the one hop in front. Without this n8n reads the
                  # proxy's own address as the client's, which turns every
                  # rate limit and every log line into a statement about
                  # 127.0.0.1.
                  N8N_PROXY_HOPS: 1
                  # Workflow code runs in the task runner rather than in the
                  # main process — the supported arrangement from 2.x, and the
                  # one that keeps a runaway Code node from taking the editor
                  # down with it.
                  N8N_RUNNERS_ENABLED: "true"
                  # Nothing about this deployment is reported anywhere. The
                  # whole point of the catalog is a server that is the owner's.
                  N8N_DIAGNOSTICS_ENABLED: "false"
                  N8N_HIRING_BANNER_ENABLED: "false"
                  # Schedule triggers ("every day at 9") are read in this zone.
                  # UTC rather than the server's, which on a rented VPS is
                  # whatever the provider set: a fixed, stated zone is one the
                  # owner can convert from, and it is changed in the workflow.
                  GENERIC_TIMEZONE: UTC
                volumes:
                  - $path/data:/home/node/.n8n
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_PORT"
              $DATABASE_SERVICE:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                environment:
                  POSTGRES_DB: $DATABASE_NAME
                  POSTGRES_USER: $DATABASE_NAME
                  POSTGRES_PASSWORD: ${SH}{DB_PASSWORD}
                volumes:
                  - $path/postgres:/var/lib/postgresql/data
            """.trimIndent(),
            envTemplate = "DB_PASSWORD=__RANDOM__"
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.n8nPath
        return listOf("""
            log "n8n: ${L10nServices.serviceStarting(context.language)}"
            install -d -m 755 $path
            # The image runs as uid 1000 and, unlike Forgejo's, does not chown
            # its own mount — a root-owned directory here is a container that
            # exits on its first write, with a permission error nobody reads.
            # 700 rather than 755: this directory holds the key that decrypts
            # every credential the workflows use.
            install -d -m 700 -o 1000 -g 1000 $path/data
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) = WebIngress(
        hostname = hostname(context),
        upstreamPort = WEB_UI_PORT,
        publicPaths = WEBHOOK_PATHS
    )

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext) = listOf("""
        echo "n8n:          https://${hostname(context)}"
        echo "  ${L10nServices.n8nOwnerWarning(context.language)}"
        echo "  ${L10nServices.n8nWebhooksPublicNote(context.language)}"
        """.trimIndent())

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.n8nPath
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
                    dataPath = "$path/data",
                    databases = listOf(BackupDatabase(
                        engine = BackupDatabase.Engine.POSTGRES,
                        service = DATABASE_SERVICE,
                        fileName = "n8n.sql"
                    )),
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/data", "$path/postgres")
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

    override fun updateSpec(context: ServiceContext) = UpdateSpec(
        images = listOf(IMAGE, DATABASE_IMAGE)
    )

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.n8nPath,
        dataPaths = listOf("${context.settings.n8nPath}/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "n8n"
        const val CONTAINER = "n8n"

        /** The database container's compose service name */
        const val DATABASE_SERVICE = "database"

        const val DATABASE_NAME = "n8n"

        /** Next free loopback port in the catalog's block */
        const val WEB_UI_PORT = 8099

        /** The port inside the container */
        const val CONTAINER_PORT = 5678

        val WRAPPER_TARGET = ServiceID.N8N.rawValue

        const val IMAGE = "n8nio/n8n:2.37.10"

        const val DATABASE_IMAGE = "postgres:16-alpine"

        /** URL path prefixes that must answer the public internet */
        val WEBHOOK_PATHS = listOf("/webhook/*", "/webhook-test/*")
    }
}

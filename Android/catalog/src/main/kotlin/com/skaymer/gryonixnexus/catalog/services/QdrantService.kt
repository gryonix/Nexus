package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.AIServicesNetwork

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
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.SharedSecrets
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class QdrantService : ManagedService {
    override val id = ServiceID.QDRANT
    override val displayName = "Qdrant"
    override val systemImage = "cylinder.split.1x2"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** A Rust service that keeps its index in memory */
    override val resources = ServiceResources(memoryMB = 512, diskGB = 2)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.qdrantPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              qdrant:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  # Read from the shared key file by the setup step below. Set
                  # here rather than baked into a config file so that rotating
                  # it is one file and one restart.
                  QDRANT__SERVICE__API_KEY: ${SH}{QDRANT_API_KEY}
                volumes:
                  - $path/storage:/qdrant/storage
                ports:
                  # Loopback, and only the REST port. The dashboard rides on
                  # the same port; whoever reaches it has the documents.
                  - "127.0.0.1:$API_PORT:6333"
            """.trimIndent() + AIServicesNetwork.COMPOSE_TAIL,
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.qdrantPath
        return listOf("""
            log "Qdrant: @STARTING@"
            install -d -m 755 $path
            install -d -m 700 $path/storage
            @KEY@
            @ENV@
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            ${AIServicesNetwork.CREATE_STEP}
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent().embedding(
                "STARTING" to L10nServices.serviceStarting(context.language),
                "KEY" to SharedSecrets.ensureSection(API_KEY_PATH),
                "ENV" to LiteLLMService.setEnvSection(
                    "$path/.env", "QDRANT_API_KEY", "${SH}(cat '$API_KEY_PATH')"
                ),
            ))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    /** None, deliberately */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext) = listOf("""
        echo "Qdrant:       127.0.0.1:$API_PORT"
        echo "  ${L10nServices.qdrantLoopbackNote(context.language)}"
        """.trimIndent())

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.qdrantPath
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
                    dataPath = "$path/storage",
                    databases = emptyList(),
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/storage")
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
        configDirectory = context.settings.qdrantPath,
        dataPaths = listOf(API_KEY_PATH, "${context.settings.qdrantPath}/storage.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "qdrant"
        const val CONTAINER = "qdrant"

        /** The REST API and the dashboard, on loopback only */
        const val API_PORT = 6333

        /** gRPC */
        const val GRPC_PORT = 6334

        val WRAPPER_TARGET = ServiceID.QDRANT.rawValue

        const val IMAGE = "qdrant/qdrant:v1.19.1"

        /** The API key both ends read */
        const val API_KEY_PATH = "${SharedSecrets.DIRECTORY}/qdrant.key"
    }
}

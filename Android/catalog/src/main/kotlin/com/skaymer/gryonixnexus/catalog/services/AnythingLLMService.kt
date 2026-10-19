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
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
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

class AnythingLLMService : ManagedService {
    override val id = ServiceID.ANYTHING_LLM
    override val displayName = "AnythingLLM"
    override val systemImage = "doc.text.magnifyingglass"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 2048, diskGB = 4)

    /** Which model backend this deployment gives it */
    enum class ModelSource { GATEWAY, ENGINE }

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.anythingLLMHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.ANYTHING_LLM, context)
        } else {
            custom
        }
    }

    fun envPath(context: ServiceContext): String =
        "${context.settings.anythingLLMPath}/anythingllm.env"

    fun modelSource(context: ServiceContext): ModelSource? = when {
        context.installedServices.contains(ServiceID.LITE_LLM) -> ModelSource.GATEWAY
        context.installedServices.contains(ServiceID.OLLAMA) -> ModelSource.ENGINE
        else -> null
    }

    fun usesQdrant(context: ServiceContext): Boolean =
        context.installedServices.contains(ServiceID.QDRANT)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.anythingLLMPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              anythingllm:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                # uid 1000, matching the directories the setup step creates.
                # Spelled out rather than left to the image so that the host
                # side and the container side cannot drift apart.
                user: "1000:1000"
                environment:
                  # The only two settings the UI must not be able to move.
                  # Everything else lives in the mounted settings file, which
                  # the container owns — see the type comment.
                  STORAGE_DIR: "/app/server/storage"
                  SERVER_PORT: $CONTAINER_PORT
                  # Chromium's own sandbox needs namespace calls docker's
                  # default seccomp profile blocks, so upstream's documented
                  # runs all add a capability instead. This buys the same
                  # feature for a far smaller grant — see the service comment.
                  ANYTHINGLLM_CHROMIUM_ARGS: "--no-sandbox"
                volumes:
                  - $path/storage:/app/server/storage
                  - $path/anythingllm.env:/app/server/.env
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_PORT"
            """.trimIndent() + AIServicesNetwork.COMPOSE_TAIL,
            envTemplate = null
        )
    }

    fun seededSettings(context: ServiceContext): List<String> {
        val lines = mutableListOf(
            "EMBEDDING_ENGINE='native'"
        )
        if (usesQdrant(context)) {
            lines += "VECTOR_DB='qdrant'"
            lines += "QDRANT_ENDPOINT='${AIServicesNetwork.url(QdrantService.CONTAINER, QdrantService.API_PORT)}'"
        } else {
            lines += "VECTOR_DB='lancedb'"
        }
        when (modelSource(context)) {
            ModelSource.GATEWAY -> {
                lines += "LLM_PROVIDER='litellm'"
                lines += "LITE_LLM_BASE_PATH='${AIServicesNetwork.url(LiteLLMService.CONTAINER, LiteLLMService.CONTAINER_PORT)}'"
            }
            ModelSource.ENGINE -> {
                lines += "LLM_PROVIDER='ollama'"
                lines += "OLLAMA_BASE_PATH='${AIServicesNetwork.url(OllamaService.CONTAINER, OllamaService.API_PORT)}'"
            }
            null -> Unit
        }
        return lines
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.anythingLLMPath
        val env = envPath(context)
        val secretSections = buildList {
            if (usesQdrant(context)) add(SharedSecrets.ensureSection(QdrantService.API_KEY_PATH))
            if (modelSource(context) == ModelSource.GATEWAY) {
                add(LiteLLMService.appKeySection(ServiceID.ANYTHING_LLM))
            }
        }
        val secrets = if (secretSections.isEmpty()) "" else "\n" + secretSections.joinToString("\n")

        val generated = buildList {
            add("""printf "SIG_KEY='%s'\n" "${SH}(openssl rand -hex 32)"""")
            add("""printf "SIG_SALT='%s'\n" "${SH}(openssl rand -hex 32)"""")
            add("""printf "JWT_SECRET='%s'\n" "${SH}(openssl rand -hex 32)"""")
            if (usesQdrant(context)) {
                add("""printf "QDRANT_API_KEY='%s'\n" "${SH}(cat '${QdrantService.API_KEY_PATH}')"""")
            }
            if (modelSource(context) == ModelSource.GATEWAY) {
                add("""printf "LITE_LLM_API_KEY='%s'\n" "${SH}(cat '${LiteLLMService.appKeyPath(ServiceID.ANYTHING_LLM)}')"""")
            }
        }.joinToString("\n") { "      $it" }
        val seeded = seededSettings(context).joinToString("\n")

        return listOf("""
            log "AnythingLLM: @STARTING@"
            install -d -m 755 $path
            # The image runs as uid 1000 and does not chown its own mounts.
            install -d -m 700 -o 1000 -g 1000 $path/storage@SECRETS@
            # Seeded ONCE and never rewritten: what the deployment derived is
            # a starting point, and the settings somebody changes in the UI
            # are written back into this same file. A re-install that rewrote
            # it would silently undo them.
            if [ ! -s '$env' ]; then
              ( umask 077
                cat > '$env' <<'EOF_ANYTHINGLLM_ENV'
            @SEEDED@
            EOF_ANYTHINGLLM_ENV
                {
            @GENERATED@
                } >> '$env'
              )
            fi
            chown 1000:1000 '$env'
            chmod 600 '$env'
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            ${AIServicesNetwork.CREATE_STEP}
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent().embedding(
                "STARTING" to L10nServices.serviceStarting(context.language),
                "SECRETS" to secrets,
                "SEEDED" to seeded,
                "GENERATED" to generated,
            ))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val lines = mutableListOf(
            """echo "AnythingLLM:  https://${hostname(context)}"""",
            """echo "  ${L10nServices.anythingLLMAdminWarning(lang)}""""
        )
        if (modelSource(context) == null) {
            lines += """echo "  ${L10nServices.anythingLLMNoModelNote(lang)}""""
        }
        lines += """echo "  ${L10nServices.anythingLLMSettingsNote(lang)}""""
        return listOf(lines.joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.anythingLLMPath
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
                    dataPath = path,
                    databases = emptyList(),
                    // SQLite and a vector index, both written continuously.
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = true,
                    sizePaths = listOf(path)
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
        configDirectory = context.settings.anythingLLMPath,
        dataPaths = listOf("${context.settings.anythingLLMPath}.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "anythingllm"
        const val CONTAINER = "anythingllm"

        /** Next free loopback port in the catalog's block */
        const val WEB_UI_PORT = 8100

        /** The port inside the container */
        const val CONTAINER_PORT = 3001

        val WRAPPER_TARGET = ServiceID.ANYTHING_LLM.rawValue

        /** Exact pinned tag */
        const val IMAGE = "mintplexlabs/anythingllm:1.16.1"
    }
}

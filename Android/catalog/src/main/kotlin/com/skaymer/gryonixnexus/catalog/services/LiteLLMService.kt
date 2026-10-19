package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.AIServicesNetwork

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupDatabase
import com.skaymer.gryonixnexus.catalog.BackupPlan
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.BackupWrapperSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.LLMProvider
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
import com.skaymer.gryonixnexus.catalog.SharedSecrets
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class LiteLLMService : ManagedService {
    override val id = ServiceID.LITE_LLM
    override val displayName = "LiteLLM"
    override val systemImage = "arrow.triangle.branch"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** A Python proxy and its small key database */
    override val resources = ServiceResources(memoryMB = 768, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.liteLLMHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.LITE_LLM, context)
        } else {
            custom
        }
    }

    /** The gateway's routing table */
    fun configYAML(context: ServiceContext): String {
        val lines = mutableListOf("model_list:")
        for (provider in LLMProvider.ALL) {
            lines.add(
                """  - model_name: "${provider.id}/*"
    litellm_params:
      model: "${provider.id}/*"
      api_key: os.environ/${provider.environmentKey}""",
            )
        }
        if (context.installedServices.contains(ServiceID.OLLAMA)) {
            lines.add(
                """  - model_name: "ollama/*"
    litellm_params:
      model: "ollama/*"
      api_base: ${AIServicesNetwork.url(OllamaService.CONTAINER, OllamaService.API_PORT)}""",
            )
        }
        lines.add("general_settings:\n  master_key: os.environ/LITELLM_MASTER_KEY")
        return lines.joinToString("\n")
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.liteLLMPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              litellm:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                depends_on:
                  - $DATABASE_SERVICE
                command: ["--config", "/app/config.yaml", "--port", "$CONTAINER_PORT"]
                environment:
                  LITELLM_MASTER_KEY: ${SH}{LITELLM_MASTER_KEY}
                  DATABASE_URL: postgresql://$DATABASE_NAME:${SH}{DB_PASSWORD}@$DATABASE_SERVICE:5432/$DATABASE_NAME
                # The provider keys, rendered by the agent from its own store.
                # A separate file from .env because nothing on the device ever
                # writes it and nothing here ever reads it back.
                env_file:
                  - $KEYS_ENV_PATH
                volumes:
                  - $path/config.yaml:/app/config.yaml:ro
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_PORT"
                networks:
                  - default
                  - ${AIServicesNetwork.NAME}
              $DATABASE_SERVICE:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                environment:
                  POSTGRES_DB: $DATABASE_NAME
                  POSTGRES_USER: $DATABASE_NAME
                  POSTGRES_PASSWORD: ${SH}{DB_PASSWORD}
                volumes:
                  - $path/postgres:/var/lib/postgresql/data
            networks:
              ${AIServicesNetwork.NAME}:
                external: true
            """.trimIndent(),
            envTemplate = null,
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.liteLLMPath
        return listOf(
            """
        log "LiteLLM: ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path
        @GATEWAY_KEY@
        # The provider keys. Created EMPTY when it is missing, because
        # compose refuses to start a service whose env_file is not there —
        # and on a deployment with no agent this file stays empty, which is
        # a gateway with no paid providers rather than a broken one.
        if [ ! -f '$KEYS_ENV_PATH' ]; then
          ( umask 077 && : > '$KEYS_ENV_PATH' )
        fi
        chmod 600 '$KEYS_ENV_PATH'
        cat > $path/config.yaml <<'EOF_LITELLM_CONFIG'
        @CONFIG@
        EOF_LITELLM_CONFIG
        @MASTER_KEY@
        if ! grep -q '^DB_PASSWORD=' $path/.env; then
          printf 'DB_PASSWORD=%s\n' "${SH}(openssl rand -hex 24)" >> $path/.env
        fi
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        ${AIServicesNetwork.CREATE_STEP}
        docker compose -p $COMPOSE_PROJECT up -d
        @APP_KEYS@
            """.trimIndent().embedding(
                "GATEWAY_KEY" to ensureGatewayKeySection(),
                "CONFIG" to configYAML(context),
                "MASTER_KEY" to setEnvSection(
                    "$path/.env", "LITELLM_MASTER_KEY", "${SH}(cat '$GATEWAY_KEY_PATH')",
                ),
                "APP_KEYS" to appKeysSection(context),
            ),
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf(
            """
        echo "LiteLLM:      https://${hostname(context)}"
        echo "  ${L10nServices.liteLLMMasterKeyLabel(lang)}: ${SH}(cat '$GATEWAY_KEY_PATH' 2>/dev/null || echo '-')"
        echo "  ${L10nServices.liteLLMKeysNote(lang)}"
        echo "  ${L10nServices.liteLLMKeysFileLabel(lang)}: $KEYS_ENV_PATH"
            """.trimIndent(),
        )
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.liteLLMPath
        return ServiceActions(
            statusProbe = StatusProbe.Container(
                name = CONTAINER,
                list = PrivilegedCommand("/usr/bin/docker", "ps -a"),
            ),
            restart = ServicePower.container(CONTAINER, "restart"),
            start = ServicePower.container(CONTAINER, "start"),
            stop = ServicePower.container(CONTAINER, "stop"),
            backup = BackupSpec.WrapperScript(
                BackupWrapperSpec(
                    wrapperTarget = WRAPPER_TARGET,
                    backupDir = context.backupDirectory(id),
                    run = ServiceCommand(
                        PrivilegedCommand(BackupWrapperSpec.WRAPPER_PATH, ""),
                        ServiceCommand.TimeoutClass.LONG,
                        streamsOutput = true,
                    ),
                    plan = BackupPlan.Archive(
                        ArchiveBackupPlan(
                            composeProject = COMPOSE_PROJECT,
                            dataPath = path,
                            databases = listOf(
                                BackupDatabase(
                                    engine = BackupDatabase.Engine.POSTGRES,
                                    service = DATABASE_SERVICE,
                                    fileName = "litellm.sql",
                                ),
                            ),
                            quiesceServices = listOf(CONTAINER),
                            encryptsByDefault = true,
                            sizePaths = listOf(path),
                            excludes = listOf("${path.split("/").last()}/postgres"),
                        ),
                    ),
                ),
            ),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = true,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, ""),
            ),
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE, DATABASE_IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.liteLLMPath,
        dataPaths = listOf(KEYS_ENV_PATH, GATEWAY_KEY_PATH),
        backupDirs = listOf(context.backupDirectory(id)),
    )

    companion object {
        const val COMPOSE_PROJECT = "litellm"
        const val CONTAINER = "litellm"

        /** Next free loopback port in the catalog's block */
        const val WEB_UI_PORT = 8098

        /** The port inside the container */
        const val CONTAINER_PORT = 4000

        val WRAPPER_TARGET = ServiceID.LITE_LLM.rawValue

        const val IMAGE = "ghcr.io/berriai/litellm:v1.100.0"
        const val DATABASE_SERVICE = "database"
        const val DATABASE_IMAGE = "postgres:16-alpine"
        const val DATABASE_NAME = "litellm"

        const val APP_KEYS_DIRECTORY = "/etc/gryonixnexus/llm-keys"

        /** The apps that present a key of their own */
        val KEYED_APPS = listOf(ServiceID.OPEN_WEB_UI, ServiceID.ANYTHING_LLM)

        /** The shared secret the gateway checks and the chat presents */
        const val GATEWAY_KEY_PATH = "/etc/gryonixnexus/llm-gateway.key"

        const val KEYS_ENV_PATH = "/etc/gryonixnexus/litellm-keys.env"

        /** The directory both of the above live in */
        const val SHARED_CONFIG_DIRECTORY = SharedSecrets.DIRECTORY

        fun ensureGatewayKeySection(): String =
            SharedSecrets.ensureSection(GATEWAY_KEY_PATH, prefix = "sk-")

        fun appKeyPath(app: ServiceID): String = "$APP_KEYS_DIRECTORY/${app.rawValue}.key"

        fun appKeySection(app: ServiceID): String {
            val key = appKeyPath(app)
            val alias = app.rawValue
            return """
                install -d -m 700 '$APP_KEYS_DIRECTORY'
                if [ ! -s '$key' ]; then
                  ( umask 077 && printf 'sk-%s\n' "${SH}(openssl rand -hex 24)" > '$key' )
                  chmod 600 '$key'
                fi
                if docker ps --format '{{.Names}}' | grep -qx '$CONTAINER'; then
                  for gnx_try in ${SH}(seq 1 60); do
                    curl -fsS -m 3 http://127.0.0.1:$WEB_UI_PORT/health/readiness >/dev/null 2>&1 && break
                    sleep 2
                  done
                  gnx_llm() {
                    printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nurl = "http://127.0.0.1:$WEB_UI_PORT/%s"\n%s' \
                      "${SH}(cat '$GATEWAY_KEY_PATH')" "${SH}1" "${SH}2" | curl -fsS -m 10 -K - >/dev/null 2>&1
                  }
                  if ! gnx_llm "key/info?key=${SH}(cat '$key')" ""; then
                    gnx_llm key/delete 'data = "{\"key_aliases\":[\"$alias\"]}"' || true
                    gnx_llm key/generate "data = \"{\\\"key\\\":\\\"${SH}(cat '$key')\\\",\\\"key_alias\\\":\\\"$alias\\\"}\"" \
                      || log "LiteLLM: $alias key not registered"
                  fi
                fi
            """.trimIndent()
        }

        /** Every installed app's key, registered once the gateway is up */
        fun appKeysSection(context: ServiceContext): String =
            KEYED_APPS.filter { context.installedServices.contains(it) }.joinToString("\n") { appKeySection(it) }

        fun setEnvSection(path: String, key: String, value: String): String = """
            touch '$path'
            chmod 600 '$path'
            if grep -q '^$key=' '$path'; then
              sed -i "s|^$key=.*|$key=$value|" '$path'
            else
              printf '%s=%s\n' '$key' "$value" >> '$path'
            fi
        """.trimIndent()
    }
}

package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.AIServicesNetwork

import com.skaymer.gryonixnexus.catalog.Apt

import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class OllamaService : ManagedService {
    override val id = ServiceID.OLLAMA
    override val displayName = "Ollama"
    override val systemImage = "cpu"
    override val category = ServiceCategory.AI
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** Idle, and deliberately not "enough to run a model" */
    override val resources = ServiceResources(memoryMB = 512, diskGB = 3)

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.ollamaPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              ollama:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  # Answer requests from the other containers on this host, not
                  # only from inside its own. The port is still bound to
                  # loopback below, so this widens nothing the outside can see.
                  OLLAMA_HOST: "0.0.0.0:$API_PORT"
                volumes:
                  # Models. The one bind mount in this catalog that is expected
                  # to reach tens of gigabytes.
                  - $path/models:/root/.ollama
                ports:
                  - "127.0.0.1:$API_PORT:$API_PORT"
            """.trimIndent() + AIServicesNetwork.COMPOSE_TAIL,
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.ollamaPath
        return listOf("""
        log "Ollama: ${L10nServices.serviceStarting(context.language)}"
        install -d -m 755 $path/models
        @GPU@
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        ${AIServicesNetwork.CREATE_STEP}
        docker compose -p $COMPOSE_PROJECT up -d
        # No model is fetched here, on purpose — see the type comment.
        """.trimIndent().embedding("GPU" to gpuSection(context)))
    }

    fun gpuSection(context: ServiceContext): String {
        val override = gpuOverridePath(context)
        if (!context.settings.ollamaUsesGPU) return "rm -f $override"
        val lang = context.language
        return """
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
          # Already taught to docker? Then nothing here needs a package or a
          # daemon restart — this step runs again on every re-install.
          if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia; then
            log "Ollama: ${L10nServices.ollamaGPUToolkitInstalling(lang)}"
            export DEBIAN_FRONTEND=noninteractive
            apt-get ${Apt.OPTIONS} install -y ca-certificates curl gnupg
            curl -fsSL $GPU_KEY_URL | gpg --batch --yes --dearmor -o $GPU_KEYRING_PATH
            # One line on purpose: this literal eats a backslash continuation before the shell ever sees it.
            curl -fsSL $GPU_SOURCE_LIST_URL | sed 's#deb https://#deb [signed-by=$GPU_KEYRING_PATH] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
            apt-get ${Apt.OPTIONS} update
            apt-get ${Apt.OPTIONS} install -y nvidia-container-toolkit
            nvidia-ctk runtime configure --runtime=docker
            # Every container on this host restarts with the daemon. Done only
            # on the run that configured the runtime, which is the first one.
            systemctl restart docker
          fi
          cat > $override <<'EOF_OLLAMA_GPU'
        @OVERRIDE@
        EOF_OLLAMA_GPU
        else
          rm -f $override
          log "Ollama: ${L10nServices.ollamaGPUMissingNote(lang)}"
        fi
        """.trimIndent().embedding("OVERRIDE" to GPU_OVERRIDE_CONTENTS)
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    /** None */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf("""
        echo "Ollama:       127.0.0.1:$API_PORT"
        echo "  ${L10nServices.ollamaNoModelsNote(lang)}"
        echo "  docker exec -it $CONTAINER ollama pull llama3.2"
        echo "  ${L10nServices.ollamaModelSizeNote(lang)}"@REPORT@
        """.trimIndent().embedding("REPORT" to gpuReportSection(context)))
    }

    fun gpuReportSection(context: ServiceContext): String {
        if (!context.settings.ollamaUsesGPU) return ""
        val lang = context.language
        return "\n" + """
        if [ -f ${gpuOverridePath(context)} ]; then
          echo "  ${L10nServices.ollamaGPUEnabledNote(lang)}"
        else
          echo "  ${L10nServices.ollamaGPUMissingNote(lang)}"
        fi
        """.trimIndent()
    }

    override fun actions(context: ServiceContext): ServiceActions = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = CONTAINER,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServicePower.container(CONTAINER, "restart"),
        start = ServicePower.container(CONTAINER, "start"),
        stop = ServicePower.container(CONTAINER, "stop")
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.ollamaPath,
        dataPaths = emptyList(),
        backupDirs = emptyList()
    )

    companion object {
        const val GPU_KEY_URL = "https://nvidia.github.io/libnvidia-container/gpgkey"
        const val GPU_SOURCE_LIST_URL =
            "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list"
        const val GPU_KEYRING_PATH = "/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"

        fun gpuOverridePath(context: ServiceContext): String =
            "${context.settings.ollamaPath}/docker-compose.override.yml"

        val GPU_OVERRIDE_CONTENTS = """
            services:
              ollama:
                deploy:
                  resources:
                    reservations:
                      devices:
                        # Every card on the host. The engine loads one model at a time
                        # and picks the device itself; enumerating them here would be a
                        # list to keep in step with the hardware.
                        - driver: nvidia
                          count: all
                          capabilities: [gpu]
            """.trimIndent()

        const val COMPOSE_PROJECT = "ollama"
        const val CONTAINER = "ollama"

        /** Loopback only */
        const val API_PORT = 11434

        /** Exact pinned tag */
        const val IMAGE = "ollama/ollama:0.33.3"
    }
}

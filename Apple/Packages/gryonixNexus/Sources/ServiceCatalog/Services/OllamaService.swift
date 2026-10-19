public struct OllamaService: ManagedService {
    public static let composeProject = "ollama"
    public static let container = "ollama"
    /// Loopback only
    public static let apiPort = 11434
    /// Exact pinned tag
    public static let image = "ollama/ollama:0.33.3"

    public static let gpuKeyURL = "https://nvidia.github.io/libnvidia-container/gpgkey"
    public static let gpuSourceListURL =
        "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list"
    public static let gpuKeyringPath =
        "/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"

    public static func gpuOverridePath(_ context: ServiceContext) -> String {
        "\(context.settings.ollamaPath)/docker-compose.override.yml"
    }

    public static let gpuOverrideContents = """
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
    """

    public let id = ServiceID.ollama
    public let displayName = "Ollama"
    public let systemImage = "cpu"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 512, diskGB: 3)

    public init() {}

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.ollamaPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              ollama:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  # Answer requests from the other containers on this host, not
                  # only from inside its own. The port is still bound to
                  # loopback below, so this widens nothing the outside can see.
                  OLLAMA_HOST: "0.0.0.0:\(Self.apiPort)"
                volumes:
                  # Models. The one bind mount in this catalog that is expected
                  # to reach tens of gigabytes.
                  - \(path)/models:/root/.ollama
                ports:
                  - "127.0.0.1:\(Self.apiPort):\(Self.apiPort)"\(AIServicesNetwork.composeTail)
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.ollamaPath
        return [
            #"""
            log "Ollama: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/models
            \#(gpuSection(context))
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            \#(AIServicesNetwork.createStep)
            docker compose -p \#(Self.composeProject) up -d
            # No model is fetched here, on purpose — see the type comment.
            """#
        ]
    }

    public func gpuSection(_ context: ServiceContext) -> String {
        let override = Self.gpuOverridePath(context)
        guard context.settings.ollamaUsesGPU else {
            return "rm -f \(override)"
        }
        let lang = context.language
        return #"""
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
          # Already taught to docker? Then nothing here needs a package or a
          # daemon restart — this step runs again on every re-install.
          if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia; then
            log "Ollama: \#(L10nServices.ollamaGPUToolkitInstalling(lang))"
            export DEBIAN_FRONTEND=noninteractive
            apt-get \#(Apt.options) install -y ca-certificates curl gnupg
            curl -fsSL \#(Self.gpuKeyURL) | gpg --batch --yes --dearmor -o \#(Self.gpuKeyringPath)
            # One line on purpose: this literal eats a backslash continuation before the shell ever sees it.
            curl -fsSL \#(Self.gpuSourceListURL) | sed 's#deb https://#deb [signed-by=\#(Self.gpuKeyringPath)] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
            apt-get \#(Apt.options) update
            apt-get \#(Apt.options) install -y nvidia-container-toolkit
            nvidia-ctk runtime configure --runtime=docker
            # Every container on this host restarts with the daemon. Done only
            # on the run that configured the runtime, which is the first one.
            systemctl restart docker
          fi
          cat > \#(override) <<'EOF_OLLAMA_GPU'
        \#(Self.gpuOverrideContents)
        EOF_OLLAMA_GPU
        else
        \#(driverMissingSection(context))
        fi
        """#
    }

    private func driverMissingSection(_ context: ServiceContext) -> String {
        let override = Self.gpuOverridePath(context)
        let lang = context.language
        guard context.settings.ollamaInstallsGPUDriver else {
            return #"""
              rm -f \#(override)
              log "Ollama: \#(L10nServices.ollamaGPUMissingNote(lang))"
            """#
        }
        return #"""
              if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi secureboot.enabled; then
                log "Ollama: \#(L10nServices.ollamaGPUSecureBootNote(lang))"
              elif command -v ubuntu-drivers >/dev/null 2>&1; then
                log "Ollama: \#(L10nServices.ollamaGPUDriverInstalling(lang))"
                export DEBIAN_FRONTEND=noninteractive
                apt-get \#(Apt.options) update
                ubuntu-drivers autoinstall
                log "Ollama: \#(L10nServices.ollamaGPUDriverInstalledNote(lang))"
              else
                log "Ollama: \#(L10nServices.ollamaGPUDriverUnsupportedNote(lang))"
              fi
              rm -f \#(override)
        """#
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    /// None
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        return [#"""
        echo "Ollama:       127.0.0.1:\#(Self.apiPort)"
        echo "  \#(L10nServices.ollamaNoModelsNote(lang))"
        echo "  docker exec -it \#(Self.container) ollama pull llama3.2"
        echo "  \#(L10nServices.ollamaModelSizeNote(lang))"\#(gpuReportSection(context))
        """#]
    }

    public func gpuReportSection(_ context: ServiceContext) -> String {
        guard context.settings.ollamaUsesGPU else { return "" }
        let lang = context.language
        return #"""

        if [ -f \#(Self.gpuOverridePath(context)) ]; then
          echo "  \#(L10nServices.ollamaGPUEnabledNote(lang))"
        else
          echo "  \#(L10nServices.ollamaGPUMissingNote(lang))"
        fi
        """#
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(
            statusProbe: .container(
                name: Self.container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.container, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.container, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.container, "stop", timeoutClass: .restart)
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.ollamaPath,
            dataPaths: [],
            backupDirs: []
        )
    }
}

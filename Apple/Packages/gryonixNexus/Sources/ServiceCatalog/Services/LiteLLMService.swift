public struct LiteLLMService: ManagedService {
    public static let composeProject = "litellm"
    public static let container = "litellm"
    /// Next free loopback port in the catalog's block
    public static let webUIPort = 8098
    /// The port inside the container
    public static let containerPort = 4000
    public static let wrapperTarget = ServiceID.liteLLM.rawValue
    public static let image = "ghcr.io/berriai/litellm:v1.100.0"
    public static let databaseService = "database"
    public static let databaseImage = "postgres:16-alpine"
    public static let databaseName = "litellm"
    public static let appKeysDirectory = "/etc/gryonixnexus/llm-keys"
    /// The apps that present a key of their own
    public static let keyedApps: [ServiceID] = [.openWebUI, .anythingLLM]

    /// The shared secret the gateway checks and the chat presents
    public static let gatewayKeyPath = "/etc/gryonixnexus/llm-gateway.key"
    public static let keysEnvPath = "/etc/gryonixnexus/litellm-keys.env"
    public static let sharedConfigDirectory = SharedSecrets.directory

    public let id = ServiceID.liteLLM
    public let displayName = "LiteLLM"
    public let systemImage = "arrow.triangle.branch"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// A Python proxy and its small key database
    public let resources = ServiceResources(memoryMB: 768, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.liteLLMHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.liteLLM, context) : custom
    }

    public static func ensureGatewayKeySection() -> String {
        SharedSecrets.ensureSection(path: gatewayKeyPath, prefix: "sk-")
    }

    public static func appKeyPath(_ app: ServiceID) -> String {
        "\(appKeysDirectory)/\(app.rawValue).key"
    }

    public static func appKeySection(_ app: ServiceID) -> String {
        let key = appKeyPath(app)
        return #"""
        install -d -m 700 '\#(appKeysDirectory)'
        if [ ! -s '\#(key)' ]; then
          ( umask 077 && printf 'sk-%s\n' "$(openssl rand -hex 24)" > '\#(key)' )
          chmod 600 '\#(key)'
        fi
        if docker ps --format '{{.Names}}' | grep -qx '\#(container)'; then
          for gnx_try in $(seq 1 60); do
            curl -fsS -m 3 http://127.0.0.1:\#(webUIPort)/health/readiness >/dev/null 2>&1 && break
            sleep 2
          done
          gnx_llm() {
            printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nurl = "http://127.0.0.1:\#(webUIPort)/%s"\n%s' \
              "$(cat '\#(gatewayKeyPath)')" "$1" "$2" | curl -fsS -m 10 -K - >/dev/null 2>&1
          }
          if ! gnx_llm "key/info?key=$(cat '\#(key)')" ""; then
            gnx_llm key/delete 'data = "{\"key_aliases\":[\"\#(app.rawValue)\"]}"' || true
            gnx_llm key/generate "data = \"{\\\"key\\\":\\\"$(cat '\#(key)')\\\",\\\"key_alias\\\":\\\"\#(app.rawValue)\\\"}\"" \
              || log "LiteLLM: \#(app.rawValue) key not registered"
          fi
        fi
        """#
    }

    /// Every installed app's key, registered once the gateway is up
    public static func appKeysSection(_ context: ServiceContext) -> String {
        keyedApps.filter { context.installedServices.contains($0) }
            .map { appKeySection($0) }
            .joined(separator: "\n")
    }

    public static func setEnvSection(path: String, key: String, value: String) -> String {
        #"""
        touch '\#(path)'
        chmod 600 '\#(path)'
        if grep -q '^\#(key)=' '\#(path)'; then
          sed -i "s|^\#(key)=.*|\#(key)=\#(value)|" '\#(path)'
        else
          printf '%s=%s\n' '\#(key)' "\#(value)" >> '\#(path)'
        fi
        """#
    }

    /// The gateway's routing table
    public func configYAML(_ context: ServiceContext) -> String {
        var lines = ["model_list:"]
        for provider in LLMProvider.all {
            lines.append("""
                  - model_name: "\(provider.id)/*"
                    litellm_params:
                      model: "\(provider.id)/*"
                      api_key: os.environ/\(provider.environmentKey)
                """)
        }
        if context.installedServices.contains(.ollama) {
            lines.append("""
                  - model_name: "ollama/*"
                    litellm_params:
                      model: "ollama/*"
                      api_base: \(AIServicesNetwork.url(OllamaService.container, OllamaService.apiPort))
                """)
        }
        lines.append("""
            general_settings:
              master_key: os.environ/LITELLM_MASTER_KEY
            """)
        return lines.joined(separator: "\n")
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.liteLLMPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              litellm:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                depends_on:
                  - \(Self.databaseService)
                command: ["--config", "/app/config.yaml", "--port", "\(Self.containerPort)"]
                environment:
                  LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
                  DATABASE_URL: postgresql://\(Self.databaseName):${DB_PASSWORD}@\(Self.databaseService):5432/\(Self.databaseName)
                # The provider keys, rendered by the agent from its own store.
                # A separate file from .env because nothing on the device ever
                # writes it and nothing here ever reads it back.
                env_file:
                  - \(Self.keysEnvPath)
                volumes:
                  - \(path)/config.yaml:/app/config.yaml:ro
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerPort)"
                networks:
                  - default
                  - \(AIServicesNetwork.name)
              \(Self.databaseService):
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  POSTGRES_DB: \(Self.databaseName)
                  POSTGRES_USER: \(Self.databaseName)
                  POSTGRES_PASSWORD: ${DB_PASSWORD}
                volumes:
                  - \(path)/postgres:/var/lib/postgresql/data
            networks:
              \(AIServicesNetwork.name):
                external: true
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.liteLLMPath
        let lang = context.language
        return [
            #"""
            log "LiteLLM: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            \#(Self.ensureGatewayKeySection())
            # The provider keys. Created EMPTY when it is missing, because
            # compose refuses to start a service whose env_file is not there —
            # and on a deployment with no agent this file stays empty, which is
            # a gateway with no paid providers rather than a broken one.
            if [ ! -f '\#(Self.keysEnvPath)' ]; then
              ( umask 077 && : > '\#(Self.keysEnvPath)' )
            fi
            chmod 600 '\#(Self.keysEnvPath)'
            cat > \#(path)/config.yaml <<'EOF_LITELLM_CONFIG'
            \#(configYAML(context))
            EOF_LITELLM_CONFIG
            \#(Self.setEnvSection(path: "\(path)/.env",
                                  key: "LITELLM_MASTER_KEY",
                                  value: "$(cat '\(Self.gatewayKeyPath)')"))
            if ! grep -q '^DB_PASSWORD=' \#(path)/.env; then
              printf 'DB_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> \#(path)/.env
            fi
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            \#(AIServicesNetwork.createStep)
            docker compose -p \#(Self.composeProject) up -d
            \#(Self.appKeysSection(context))
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        return [#"""
        echo "LiteLLM:      https://\#(hostname(context))"
        echo "  \#(L10nServices.liteLLMMasterKeyLabel(lang)): $(cat '\#(Self.gatewayKeyPath)' 2>/dev/null || echo '-')"
        echo "  \#(L10nServices.liteLLMKeysNote(lang))"
        echo "  \#(L10nServices.liteLLMKeysFileLabel(lang)): \#(Self.keysEnvPath)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.liteLLMPath
        return ServiceActions(
            statusProbe: .container(
                name: Self.container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.container, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.container, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.container, "stop", timeoutClass: .restart),
            backup: .wrapperScript(BackupWrapperSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                run: ServiceCommand(
                    PrivilegedCommand(binaryPath: BackupWrapperSpec.wrapperPath, arguments: ""),
                    timeoutClass: .long,
                    streamsOutput: true
                ),
                plan: .archive(ArchiveBackupPlan(
                    composeProject: Self.composeProject,
                    dataPath: path,
                    databases: [BackupDatabase(engine: .postgres,
                                               service: Self.databaseService,
                                               fileName: "litellm.sql")],
                    quiesceServices: [Self.container],
                    encryptsByDefault: true,
                    sizePaths: [path],
                    excludes: ["\(path.split(separator: "/").last.map(String.init) ?? path)/postgres"]
                ))
            )),
            restore: RestoreSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                needsPassphrase: true,
                privileged: PrivilegedCommand(binaryPath: RestoreSpec.wrapperPath, arguments: "")
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image, Self.databaseImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.liteLLMPath,
            dataPaths: [Self.keysEnvPath, Self.gatewayKeyPath],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

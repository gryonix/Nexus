public struct QdrantService: ManagedService {
    public static let composeProject = "qdrant"
    public static let container = "qdrant"
    /// The REST API and the dashboard, on loopback only
    public static let apiPort = 6333
    /// gRPC
    public static let grpcPort = 6334
    public static let wrapperTarget = ServiceID.qdrant.rawValue
    public static let image = "qdrant/qdrant:v1.19.1"

    /// The API key both ends read
    public static let apiKeyPath = "\(SharedSecrets.directory)/qdrant.key"

    public let id = ServiceID.qdrant
    public let displayName = "Qdrant"
    public let systemImage = "cylinder.split.1x2"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// A Rust service that keeps its index in memory
    public let resources = ServiceResources(memoryMB: 512, diskGB: 2)

    public init() {}

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.qdrantPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              qdrant:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  # Read from the shared key file by the setup step below. Set
                  # here rather than baked into a config file so that rotating
                  # it is one file and one restart.
                  QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
                volumes:
                  - \(path)/storage:/qdrant/storage
                ports:
                  # Loopback, and only the REST port. The dashboard rides on
                  # the same port; whoever reaches it has the documents.
                  - "127.0.0.1:\(Self.apiPort):6333"\(AIServicesNetwork.composeTail)
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.qdrantPath
        return [
            #"""
            log "Qdrant: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)
            install -d -m 700 \#(path)/storage
            \#(SharedSecrets.ensureSection(path: Self.apiKeyPath))
            \#(LiteLLMService.setEnvSection(path: "\(path)/.env",
                                            key: "QDRANT_API_KEY",
                                            value: "$(cat '\(Self.apiKeyPath)')"))
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            \#(AIServicesNetwork.createStep)
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    /// None, deliberately
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        [#"""
        echo "Qdrant:       127.0.0.1:\#(Self.apiPort)"
        echo "  \#(L10nServices.qdrantLoopbackNote(context.language))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.qdrantPath
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
                    dataPath: "\(path)/storage",
                    databases: [],
                    quiesceServices: [Self.container],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/storage"]
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
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.qdrantPath,
            dataPaths: [Self.apiKeyPath,
                        "\(context.settings.qdrantPath)/storage.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

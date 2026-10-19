public struct N8NService: ManagedService {
    public static let composeProject = "n8n"
    public static let container = "n8n"
    /// The database container's compose service name
    public static let databaseService = "database"
    /// Next free loopback port in the catalog's block
    public static let webUIPort = 8099
    /// The port inside the container
    public static let containerPort = 5678
    public static let wrapperTarget = ServiceID.n8n.rawValue
    public static let image = "n8nio/n8n:2.37.10"
    public static let databaseImage = "postgres:16-alpine"
    public static let databaseName = "n8n"

    /// URL path prefixes that must answer the public internet
    public static let webhookPaths = ["/webhook/*", "/webhook-test/*"]

    public let id = ServiceID.n8n
    public let displayName = "n8n"
    public let systemImage = "arrow.triangle.branch"
    public let category = ServiceCategory.automation
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// Node with a PostgreSQL beside it
    public let resources = ServiceResources(memoryMB: 1024, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.n8nHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.n8n, context) : custom
    }

    public func baseURL(_ context: ServiceContext) -> String {
        "https://\(hostname(context))/"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.n8nPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              n8n:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                depends_on:
                  - \(Self.databaseService)
                environment:
                  DB_TYPE: postgresdb
                  DB_POSTGRESDB_HOST: \(Self.databaseService)
                  DB_POSTGRESDB_DATABASE: \(Self.databaseName)
                  DB_POSTGRESDB_USER: \(Self.databaseName)
                  DB_POSTGRESDB_PASSWORD: ${DB_PASSWORD}
                  # Both halves of "which address is this?": the first is what
                  # n8n checks incoming requests against, the second is what it
                  # PRINTS into every webhook URL and every editor link.
                  N8N_HOST: \(hostname(context))
                  WEBHOOK_URL: "\(baseURL(context))"
                  N8N_EDITOR_BASE_URL: "\(baseURL(context))"
                  N8N_PROTOCOL: https
                  N8N_PORT: \(Self.containerPort)
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
                  - \(path)/data:/home/node/.n8n
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerPort)"
              \(Self.databaseService):
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  POSTGRES_DB: \(Self.databaseName)
                  POSTGRES_USER: \(Self.databaseName)
                  POSTGRES_PASSWORD: ${DB_PASSWORD}
                volumes:
                  - \(path)/postgres:/var/lib/postgresql/data
            """,
            envTemplate: """
            DB_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.n8nPath
        return [
            #"""
            log "n8n: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)
            # The image runs as uid 1000 and, unlike Forgejo's, does not chown
            # its own mount — a root-owned directory here is a container that
            # exits on its first write, with a permission error nobody reads.
            # 700 rather than 755: this directory holds the key that decrypts
            # every credential the workflows use.
            install -d -m 700 -o 1000 -g 1000 \#(path)/data
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort,
                   publicPaths: Self.webhookPaths)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        return [
            #"""
            echo "n8n:          https://\#(hostname(context))"
            echo "  \#(L10nServices.n8nOwnerWarning(lang))"
            echo "  \#(L10nServices.n8nWebhooksPublicNote(lang))"
            """#
        ]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.n8nPath
        return ServiceActions(
            statusProbe: .composeProject(
                project: Self.composeProject,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                        arguments: "compose -p \(Self.composeProject) ps")
            ),
            restart: ServicePower.compose(project: Self.composeProject, "restart", timeoutClass: .restart),
            start: ServicePower.compose(project: Self.composeProject, "start", timeoutClass: .restart),
            stop: ServicePower.compose(project: Self.composeProject, "stop", timeoutClass: .restart),
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
                    dataPath: "\(path)/data",
                    databases: [BackupDatabase(engine: .postgres,
                                               service: Self.databaseService,
                                               fileName: "n8n.sql")],
                    quiesceServices: [Self.container],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/data", "\(path)/postgres"]
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
            configDirectory: context.settings.n8nPath,
            dataPaths: ["\(context.settings.n8nPath)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

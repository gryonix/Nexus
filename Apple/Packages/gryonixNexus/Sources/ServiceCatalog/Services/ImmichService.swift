public struct ImmichService: ManagedService {
    public static let composeProject = "immich"
    public static let webUIPort = 2283
    public static let wrapperTarget = ServiceID.immich.rawValue
    public static let image = "ghcr.io/immich-app/immich-server:v3"
    /// Face and object recognition
    public static let machineLearningImage = "ghcr.io/immich-app/immich-machine-learning:v3"
    /// Redis-compatible cache (valkey), as upstream's own compose file uses
    public static let cacheImage = "docker.io/valkey/valkey:8-bookworm"
    public static let databaseImage = "ghcr.io/immich-app/postgres:16-vectorchord0.4.3"

    public let id = ServiceID.immich
    public let displayName = "Immich"
    public let systemImage = "photo.on.rectangle.angled"
    public let category = ServiceCategory.photos
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 1536, diskGB: 4)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.immichHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.immich, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.immichPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              immich-server:
                image: \(Self.image)
                restart: unless-stopped
                depends_on:
                  - redis
                  - database
                environment:
                  DB_HOSTNAME: database
                  DB_USERNAME: postgres
                  DB_PASSWORD: ${DB_PASSWORD}
                  DB_DATABASE_NAME: immich
                  REDIS_HOSTNAME: redis
                  IMMICH_SERVER_URL: https://\(hostname(context))
                volumes:
                  - \(path)/library:/usr/src/app/upload
                  - /etc/localtime:/etc/localtime:ro
                ports:
                  - "127.0.0.1:\(Self.webUIPort):2283"
              immich-machine-learning:
                image: \(Self.machineLearningImage)
                restart: unless-stopped
                volumes:
                  - \(path)/ml-cache:/cache
              redis:
                image: \(Self.cacheImage)
                restart: unless-stopped
              database:
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  POSTGRES_PASSWORD: ${DB_PASSWORD}
                  POSTGRES_USER: postgres
                  POSTGRES_DB: immich
                volumes:
                  - \(path)/postgres:/var/lib/postgresql/data
            """,
            envTemplate: """
            DB_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.immichPath
        return [
            #"""
            log "Immich: \#(L10nServices.serviceStarting(context.language))"
            install -d \#(path)
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
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
        [#"""
        echo "Immich:       https://\#(hostname(context))"
        echo "  \#(L10nServices.immichAdminWarning(context.language))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.immichPath
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
                    dataPath: "\(path)/library",
                    databases: [BackupDatabase(engine: .postgres, service: "database",
                                               fileName: "immich.sql")],
                    quiesceServices: [],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/library", "\(path)/postgres"]
                ))
            )),
            restore: RestoreSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                needsPassphrase: false,
                privileged: PrivilegedCommand(binaryPath: RestoreSpec.wrapperPath, arguments: "")
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image, Self.machineLearningImage,
                            Self.cacheImage, Self.databaseImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.immichPath,
            dataPaths: ["\(context.settings.immichPath)/library.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

public struct PhotoPrismService: ManagedService {
    public static let composeProject = "photoprism"
    public static let container = "photoprism"
    public static let webUIPort = 2342
    public static let wrapperTarget = ServiceID.photoprism.rawValue
    public static let image = "photoprism/photoprism:260728"
    public static let databaseImage = "mariadb:11"

    public let id = ServiceID.photoprism
    public let displayName = "PhotoPrism"
    public let systemImage = "photo.stack"
    public let category = ServiceCategory.photos
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 2048, diskGB: 6)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.photoprismHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.photoprism, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.photoprismPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              mariadb:
                image: \(Self.databaseImage)
                restart: unless-stopped
                command: --transaction-isolation=READ-COMMITTED --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --max-connections=512 --innodb-rollback-on-timeout=OFF --innodb-lock-wait-timeout=120
                environment:
                  MARIADB_AUTO_UPGRADE: "1"
                  MARIADB_INITDB_SKIP_TZINFO: "1"
                  # The MYSQL_* spellings, not upstream's MARIADB_*: the shared
                  # backup wrapper dumps a database by reading
                  # MYSQL_ROOT_PASSWORD and MYSQL_DATABASE out of the
                  # container's OWN environment (a password passed from the
                  # host would sit in the argv of docker exec, readable from
                  # /proc). The image accepts both spellings; only one of them
                  # makes the backup work.
                  MYSQL_DATABASE: photoprism
                  MYSQL_USER: photoprism
                  MYSQL_PASSWORD: ${MYSQL_PASSWORD}
                  MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
                volumes:
                  - \(path)/db:/var/lib/mysql
              photoprism:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                depends_on:
                  - mariadb
                working_dir: "/photoprism"
                environment:
                  PHOTOPRISM_ADMIN_USER: \(context.settings.adminUsername)
                  PHOTOPRISM_ADMIN_PASSWORD: ${PHOTOPRISM_ADMIN_PASSWORD}
                  # Password auth, never the public mode: this is a public
                  # hostname, and "public" means the library is too.
                  PHOTOPRISM_AUTH_MODE: "password"
                  PHOTOPRISM_SITE_URL: "https://\(hostname(context))/"
                  # Caddy terminates TLS and speaks plain HTTP to this port;
                  # left at its default PhotoPrism would serve its own
                  # self-signed certificate and the proxy would not trust it.
                  PHOTOPRISM_DISABLE_TLS: "true"
                  PHOTOPRISM_DEFAULT_TLS: "false"
                  PHOTOPRISM_DATABASE_DRIVER: "mysql"
                  PHOTOPRISM_DATABASE_SERVER: "mariadb:3306"
                  PHOTOPRISM_DATABASE_NAME: "photoprism"
                  PHOTOPRISM_DATABASE_USER: "photoprism"
                  PHOTOPRISM_DATABASE_PASSWORD: ${MYSQL_PASSWORD}
                  # Sidecar YAML on: it is what lets the metadata be rebuilt
                  # from the originals alone, and the originals are what the
                  # backup carries.
                  PHOTOPRISM_SIDECAR_YAML: "true"
                  PHOTOPRISM_BACKUP_ALBUMS: "true"
                volumes:
                  - \(path)/originals:/photoprism/originals
                  - \(path)/storage:/photoprism/storage
                ports:
                  - "127.0.0.1:\(Self.webUIPort):2342"
            """,
            envTemplate: """
            MYSQL_ROOT_PASSWORD=__RANDOM__
            MYSQL_PASSWORD=__RANDOM__
            PHOTOPRISM_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.photoprismPath
        return [
            #"""
            log "PhotoPrism: \#(L10nServices.serviceStarting(context.language))"
            # Modes are spelled out rather than left to the umask: PhotoPrism
            # drops to its own user and has to write into both of these.
            install -d -m 755 \#(path)/originals \#(path)/storage
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
        let path = context.settings.photoprismPath
        let lang = context.language
        return [#"""
        echo "PhotoPrism:   https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): \#(context.settings.adminUsername)"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^PHOTOPRISM_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        echo "  \#(L10nServices.photoprismOriginalsLabel(lang)): \#(path)/originals"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.photoprismPath
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
                    dataPath: "\(path)/originals",
                    databases: [BackupDatabase(engine: .mysql, service: "mariadb",
                                               fileName: "photoprism.sql")],
                    quiesceServices: [],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/originals", "\(path)/storage", "\(path)/db"]
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
        UpdateSpec(images: [Self.image, Self.databaseImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.photoprismPath,
            dataPaths: ["\(context.settings.photoprismPath)/originals.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

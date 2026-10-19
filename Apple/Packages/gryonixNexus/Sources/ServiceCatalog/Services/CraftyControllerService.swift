public struct CraftyControllerService: ManagedService {
    public static let composeProject = "crafty"
    public static let container = "crafty"
    public static let webUIPort = 8095
    public static let wrapperTarget = ServiceID.craftyController.rawValue
    /// Pinned release
    public static let image = "registry.gitlab.com/crafty-controller/crafty-4:4.9.0"

    public let id = ServiceID.craftyController
    public let displayName = "Crafty Controller"
    public let systemImage = "slider.horizontal.3"
    public let category = ServiceCategory.implicit
    /// The games shelf brought it — see `ManagedService.displayCategory`
    public let displayCategory = ServiceCategory.games
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 512, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.craftyHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.craftyController, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.craftyPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              crafty:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  TZ: "Etc/UTC"
                volumes:
                  - \(path)/backups:/crafty/backups
                  - \(path)/logs:/crafty/logs
                  - \(path)/servers:/crafty/servers
                  - \(path)/config:/crafty/app/config
                  - \(path)/import:/crafty/import
                ports:
                  # Loopback only — Caddy publishes the name, and the panel is
                  # an admin surface like every other one in this catalog.
                  - "127.0.0.1:\(Self.webUIPort):8443"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.craftyPath
        return [
            #"""
            log "Crafty Controller: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/backups \#(path)/logs \#(path)/servers \#(path)/config \#(path)/import
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context),
                   upstreamPort: Self.webUIPort,
                   adminGuard: true,
                   upstreamHTTPS: true)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        return [#"""
        echo "Crafty Controller: https://\#(hostname(context))"
        echo "  \#(L10nServices.craftyFirstLogin(lang)): \#(context.settings.craftyPath)/config/default-creds.txt"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.craftyPath
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
                    dataPath: "\(path)/config",
                    databases: [],
                    // SQLite, written while the panel runs.
                    quiesceServices: [Self.container],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/config"]
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
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.craftyPath,
            dataPaths: ["\(context.settings.craftyPath)/config",
                        "\(context.settings.craftyPath)/servers"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

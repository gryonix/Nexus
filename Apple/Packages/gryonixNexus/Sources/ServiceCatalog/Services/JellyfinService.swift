public struct JellyfinService: ManagedService {
    public static let composeProject = "jellyfin"
    public static let container = "jellyfin"
    public static let webUIPort = 8096
    public static let wrapperTarget = ServiceID.jellyfin.rawValue
    public static let image = "jellyfin/jellyfin:10.11.11"

    public let id = ServiceID.jellyfin
    public let displayName = "Jellyfin"
    public let systemImage = "play.rectangle"
    public let category = ServiceCategory.media
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 768, diskGB: 3)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.jellyfinHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.jellyfin, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.jellyfinPath
        let media = context.settings.jellyfinMediaPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              jellyfin:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  # Jellyfin builds absolute URLs for clients from this.
                  JELLYFIN_PublishedServerUrl: "https://\(hostname(context))"
                volumes:
                  - \(path)/config:/config
                  - \(path)/cache:/cache
                  # Read-only: a media server has no business writing to the
                  # library, and a mistake in the UI would delete originals.
                  - \(media):/media:ro
                ports:
                  - "127.0.0.1:\(Self.webUIPort):8096"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.jellyfinPath
        let media = context.settings.jellyfinMediaPath
        return [
            #"""
            log "Jellyfin: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/config \#(path)/cache
            # The library directory is created only if it is missing: pointing
            # at an existing library is the normal case, and its ownership and
            # mode are then the user's business, not ours.
            [ -d \#(media) ] || install -d -m 755 \#(media)
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
        let lang = context.language
        return [#"""
        echo "Jellyfin:     https://\#(hostname(context))"
        echo "  \#(L10nServices.jellyfinAdminWarning(lang))"
        echo "  \#(L10nServices.jellyfinLibraryLabel(lang)): \#(context.settings.jellyfinMediaPath)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.jellyfinPath
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
            configDirectory: context.settings.jellyfinPath,
            dataPaths: ["\(context.settings.jellyfinPath)/config.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

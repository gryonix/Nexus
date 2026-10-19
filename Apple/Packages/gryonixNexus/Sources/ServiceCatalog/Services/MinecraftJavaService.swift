public struct MinecraftJavaService: ManagedService {
    public static let composeProject = "minecraft-java"
    public static let container = "minecraft-java"
    public static let wrapperTarget = ServiceID.minecraftJava.rawValue
    public static let image = "itzg/minecraft-server:2026.8.1-java25"
    /// RCON, on loopback only
    public static let rconPort = 25575

    public let id = ServiceID.minecraftJava
    public let displayName = "Minecraft (Java)"
    public let systemImage = "gamecontroller"
    public let category = ServiceCategory.games
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 3072, diskGB: 8)

    public init() {}

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let settings = context.settings
        let path = settings.minecraftJavaPath
        let version = settings.minecraftJavaVersion.trimmingCharacters(in: .whitespaces)
        let whitelist = settings.minecraftJavaWhitelist.trimmingCharacters(in: .whitespaces)
        let operators = settings.minecraftJavaOperators.trimmingCharacters(in: .whitespaces)
        let mods = settings.minecraftJavaMods.trimmingCharacters(in: .whitespaces)
        var environment = [
            #"      EULA: "\#(settings.minecraftJavaAcceptsEULA ? "TRUE" : "FALSE")""#,
            #"      TYPE: "\#(settings.minecraftJavaFlavour)""#,
            #"      MEMORY: "\#(settings.minecraftJavaMemoryMB)M""#,
            "      # Enabled so the panel and the backup wrapper can ask a",
            "      # RUNNING server to flush its world before anything reads it.",
            #"      ENABLE_RCON: "true""#,
            #"      RCON_PASSWORD: "${RCON_PASSWORD}""#
        ]
        if !version.isEmpty {
            environment.append(#"      VERSION: "\#(version)""#)
        }
        if !whitelist.isEmpty {
            environment.append(#"      WHITELIST: "\#(whitelist)""#)
            environment.append(#"      ENFORCE_WHITELIST: "true""#)
        }
        if !operators.isEmpty {
            environment.append(#"      OPS: "\#(operators)""#)
        }
        if !mods.isEmpty {
            environment.append(#"      MODRINTH_PROJECTS: "\#(mods)""#)
            environment.append(#"      MODRINTH_DOWNLOAD_DEPENDENCIES: "required""#)
        }
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              minecraft-java:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                # The server reads commands from its own stdin, and that is how
                # both a clean stop and the panel's console work. Without these
                # two the container can only be killed, which is how a world
                # gets corrupted.
                stdin_open: true
                tty: true
                environment:
            \(environment.joined(separator: "\n"))
                volumes:
                  - \(path)/data:/data
                  # The image's own drop-in directories, and this is where an
                  # uploaded file lands: content here is SYNCHRONISED into
                  # /data/mods (and /data/plugins) at every start, so a jar the
                  # owner sent from the app survives a restart, an image update
                  # and every change to the Modrinth list — which manages only
                  # what it installed itself. Read-only: the server has no
                  # business writing back into what somebody uploaded.
                  #
                  # Both, always, because the answer to "mods or plugins?" is
                  # the TYPE, and the TYPE is a setting that can change on a
                  # server that already exists.
                  - \(path)/mods:/mods:ro
                  - \(path)/plugins:/plugins:ro
                ports:
                  - "\(settings.minecraftJavaPort):25565"
                  # RCON stays on loopback: its password is the whole of its
                  # security, and the panel reaches it from the same host.
                  - "127.0.0.1:\(Self.rconPort):25575"
            """,
            envTemplate: "RCON_PASSWORD=__RANDOM__"
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.minecraftJavaPath
        return [
            #"""
            log "Minecraft (Java): \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/data \#(path)/mods \#(path)/plugins
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(context.settings.minecraftJavaPort, .tcp, comment: "Minecraft (Java)")]
    }

    /// None
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        ["play.\(context.domain)"]
    }

    public func serviceRecords(_ context: ServiceContext) -> [ServiceRecord] {
        [ServiceRecord(
            name: "_minecraft._tcp.\(context.domain)",
            port: context.settings.minecraftJavaPort,
            target: "play.\(context.domain)"
        )]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let settings = context.settings
        let lang = context.language
        let address = settings.minecraftJavaPort == 25565
            ? "play.\(context.domain)"
            : "play.\(context.domain):\(settings.minecraftJavaPort)"
        var lines = [#"""
        echo "Minecraft (Java):  \#(address)"
        echo "  \#(L10nServices.minecraftFlavourLabel(lang)): \#(settings.minecraftJavaFlavour)"
        """#]
        if !settings.minecraftJavaAcceptsEULA {
            lines.append(#"""
            echo "  \#(L10nServices.minecraftEULANotAccepted(lang))"
            """#)
        }
        if settings.minecraftJavaVersion.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(#"""
            echo "  \#(L10nServices.minecraftVersionFollowsLatest(lang))"
            """#)
        }
        if settings.minecraftJavaWhitelist.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(#"""
            echo "  \#(L10nServices.minecraftNoWhitelist(lang))"
            """#)
        }
        let mods = settings.minecraftJavaMods.trimmingCharacters(in: .whitespaces)
        if !mods.isEmpty {
            lines.append(#"""
            echo "  \#(L10nServices.minecraftModsLabel(lang)): \#(mods)"
            """#)
            if settings.minecraftJavaFlavour == "VANILLA" {
                lines.append(#"""
                echo "  \#(L10nServices.minecraftModsNeedLoader(lang))"
                """#)
            } else if settings.minecraftJavaFlavour != "PAPER" {
                lines.append(#"""
                echo "  \#(L10nServices.minecraftModsClientSide(lang))"
                """#)
            }
        }
        return lines
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.minecraftJavaPath
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
                    dataPath: "\(path)/data",
                    databases: [],
                    quiesceServices: [Self.container],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/data"]
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
            configDirectory: context.settings.minecraftJavaPath,
            dataPaths: ["\(context.settings.minecraftJavaPath)/data"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

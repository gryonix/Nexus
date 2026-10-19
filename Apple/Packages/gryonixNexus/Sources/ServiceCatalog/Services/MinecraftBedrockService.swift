public struct MinecraftBedrockService: ManagedService {
    public static let composeProject = "minecraft-bedrock"
    public static let container = "minecraft-bedrock"
    public static let wrapperTarget = ServiceID.minecraftBedrock.rawValue
    public static let image = "itzg/minecraft-bedrock-server:2026.8.2"

    public let id = ServiceID.minecraftBedrock
    public let displayName = "Minecraft (Bedrock)"
    public let systemImage = "gamecontroller.fill"
    public let category = ServiceCategory.games
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 1024, diskGB: 4)

    public init() {}

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let settings = context.settings
        let path = settings.minecraftBedrockPath
        let version = settings.minecraftBedrockVersion.trimmingCharacters(in: .whitespaces)
        var environment = [
            #"      EULA: "\#(settings.minecraftBedrockAcceptsEULA ? "TRUE" : "FALSE")""#,
            #"      SERVER_PORT: "\#(settings.minecraftBedrockPort)""#
        ]
        if !version.isEmpty {
            environment.append(#"      VERSION: "\#(version)""#)
        }
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              minecraft-bedrock:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                # Same reason as the Java server: a clean stop is a command
                # written to the server's stdin, and without a terminal the
                # only way out is a kill.
                stdin_open: true
                tty: true
                environment:
            \(environment.joined(separator: "\n"))
                volumes:
                  - \(path)/data:/data
                ports:
                  # UDP, and that is the whole protocol — Bedrock is RakNet
                  # over UDP, so a TCP rule here would open nothing at all.
                  - "\(settings.minecraftBedrockPort):\(settings.minecraftBedrockPort)/udp"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.minecraftBedrockPath
        return [
            #"""
            log "Minecraft (Bedrock): \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/data
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            # The x86 emulator on ARM needs a 4 KB page kernel
            if [ "$(uname -m)" = aarch64 ] && [ "$(getconf PAGESIZE)" != 4096 ]; then
              log "Minecraft (Bedrock): \#(L10nServices.minecraftBedrockNeedsSmallPages(context.language))"
            else
              docker compose -p \#(Self.composeProject) up -d
            fi
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(context.settings.minecraftBedrockPort, .udp, comment: "Minecraft (Bedrock)")]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        ["play.\(context.domain)"]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let settings = context.settings
        let lang = context.language
        var lines = [#"""
        echo "Minecraft (Bedrock): play.\#(context.domain):\#(settings.minecraftBedrockPort)"
        echo "  \#(L10nServices.minecraftBedrockOnArm(lang))"
        """#]
        if !settings.minecraftBedrockAcceptsEULA {
            lines.append(#"""
            echo "  \#(L10nServices.minecraftEULANotAccepted(lang))"
            """#)
        }
        return lines
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.minecraftBedrockPath
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
            configDirectory: context.settings.minecraftBedrockPath,
            dataPaths: ["\(context.settings.minecraftBedrockPath)/data"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

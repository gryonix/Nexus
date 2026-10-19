/// The MQTT broker the house talks over, at home only.
public struct MosquittoService: ManagedService {
    public static let composeProject = "mosquitto"
    public static let container = "mosquitto"
    /// The broker's own port, reachable from the home network
    public static let brokerPort = 1883
    public static let wrapperTarget = ServiceID.mosquitto.rawValue
    public static let image = "eclipse-mosquitto:2.0.22"
    /// Both clients this project installs sign in with it
    public static let users = ["homeassistant", "zigbee2mqtt"]

    public let id = ServiceID.mosquitto
    public let displayName = "Mosquitto"
    public let systemImage = "dot.radiowaves.left.and.right"
    public let category = ServiceCategory.smartHome
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 128, diskGB: 1)
    public let requiresHomeMachine = true

    public init() {}

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.mosquittoPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              mosquitto:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                volumes:
                  - \(path)/config:/mosquitto/config
                  - \(path)/data:/mosquitto/data
                ports:
                  # The devices in the house speak to it directly.
                  - "\(Self.brokerPort):1883"
            """,
            envTemplate: """
            MQTT_PASSWORD=__RANDOM__
            """
        )
    }

    /// Anonymous clients are refused; the password file admits
    public static let brokerConfiguration = """
        listener 1883
        allow_anonymous false
        password_file /mosquitto/config/passwd
        persistence true
        persistence_location /mosquitto/data/
        """

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.mosquittoPath
        let config = "\(path)/config"
        let accounts = Self.users.map { #"\#($0) "$MQTT_PASSWORD""# }.joined(separator: " ")
        return [
            #"""
            log "Mosquitto: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(config) \#(path)/data
            cat > \#(config)/mosquitto.conf <<'EOF_MQTT_CONF'
            \#(Self.brokerConfiguration)
            EOF_MQTT_CONF
            . \#(path)/.env
            if [ ! -f \#(config)/passwd ]; then
              install -m 600 /dev/null \#(config)/passwd
              printf '%s:%s\n' \#(accounts) >> \#(config)/passwd
              docker run --rm -v \#(config):/mosquitto/config \#(Self.image) \
                mosquitto_passwd -U /mosquitto/config/passwd
              docker run --rm -v \#(config):/mosquitto/config \#(Self.image) \
                chown 1883:1883 /mosquitto/config/passwd
            fi
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(Self.brokerPort, .tcp, comment: "MQTT (home network)")]
    }

    /// None: a broker speaks MQTT, not HTTP
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let path = context.settings.mosquittoPath
        return [#"""
        echo "Mosquitto:    \#(L10nServices.mosquittoNetworkAddress(lang)):\#(Self.brokerPort)"
        echo "  \#(L10nServices.mosquittoAccountsLabel(lang)): \#(Self.users.joined(separator: ", "))"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^MQTT_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.mosquittoPath
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
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/config", "\(path)/data"]
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
            configDirectory: context.settings.mosquittoPath,
            dataPaths: ["\(context.settings.mosquittoPath)/config.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

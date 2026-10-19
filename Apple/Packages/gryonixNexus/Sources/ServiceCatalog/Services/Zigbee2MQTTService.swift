/// Zigbee devices without a vendor hub of their own.
public struct Zigbee2MQTTService: ManagedService {
    public static let composeProject = "zigbee2mqtt"
    public static let container = "zigbee2mqtt"
    public static let webUIPort = 8103
    public static let wrapperTarget = ServiceID.zigbee2MQTT.rawValue
    public static let image = "koenkk/zigbee2mqtt:2.14.1"
    /// The broker account this one signs in with
    public static let mqttUser = "zigbee2mqtt"

    public let id = ServiceID.zigbee2MQTT
    public let displayName = "Zigbee2MQTT"
    public let systemImage = "antenna.radiowaves.left.and.right"
    public let category = ServiceCategory.smartHome
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 256, diskGB: 1)
    public let requiresHomeMachine = true

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.zigbee2MQTTHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.zigbee2MQTT, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.zigbee2MQTTPath
        let stick = context.settings.homeAssistantUSBDevice
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              zigbee2mqtt:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                volumes:
                  - \(path)/data:/app/data
                  # Device names as udev knows them.
                  - /run/udev:/run/udev:ro
                devices:
                  - \(stick):\(stick)
                # The broker it publishes to and the page it serves are both
                # on the host's own network; published ports would be ignored.
                network_mode: host
            """,
            envTemplate: nil
        )
    }

    /// The settings file, written once with the broker's own password
    public static func initialConfiguration(stick: String, password: String) -> String {
        """
        mqtt:
          server: mqtt://127.0.0.1:\(MosquittoService.brokerPort)
          user: \(Self.mqttUser)
          password: \(password)
        serial:
          port: \(stick)
        frontend:
          enabled: true
          host: 127.0.0.1
          port: \(Self.webUIPort)
        """
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.zigbee2MQTTPath
        let broker = context.settings.mosquittoPath
        let stick = context.settings.homeAssistantUSBDevice
        let settings = Self.initialConfiguration(stick: stick, password: "$MQTT_PASSWORD")
        return [
            #"""
            log "Zigbee2MQTT: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/data
            . \#(broker)/.env
            if [ ! -f \#(path)/data/configuration.yaml ]; then
              install -m 600 /dev/null \#(path)/data/configuration.yaml
              cat > \#(path)/data/configuration.yaml <<EOF_Z2M_CONFIG
            \#(settings)
            EOF_Z2M_CONFIG
            fi
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
        echo "Zigbee2MQTT:  https://\#(hostname(context))"
        echo "  \#(L10nServices.zigbee2MQTTPairingHint(context.language))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.zigbee2MQTTPath
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
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/data"]
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
            configDirectory: context.settings.zigbee2MQTTPath,
            dataPaths: ["\(context.settings.zigbee2MQTTPath)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

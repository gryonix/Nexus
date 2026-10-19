/// The smart-home hub: one container on the host network, at home only.
public struct HomeAssistantService: ManagedService {
    public static let composeProject = "home-assistant"
    public static let container = "homeassistant"
    public static let webUIPort = 8123
    public static let wrapperTarget = ServiceID.homeAssistant.rawValue
    public static let image = "homeassistant/home-assistant:2026.9.3"

    public let id = ServiceID.homeAssistant
    public let displayName = "Home Assistant"
    public let systemImage = "house"
    public let category = ServiceCategory.smartHome
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 1024, diskGB: 3)
    public let requiresHomeMachine = true

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.homeAssistantHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.homeAssistant, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.homeAssistantPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              homeassistant:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                # Discovery (mDNS, SSDP) only works on the home network itself.
                network_mode: host
                # Bluetooth adapter management, through the host's BlueZ.
                cap_add:
                  - NET_ADMIN
                  - NET_RAW
                volumes:
                  - \(path)/config:/config
                  - /etc/localtime:/etc/localtime:ro
                  # Bluetooth devices, through the host's BlueZ.
                  - /run/dbus:/run/dbus:ro\(Self.deviceLines(context))
            """,
            envTemplate: nil
        )
    }

    /// A Zigbee or Z-Wave stick, passed through by path
    static func deviceLines(_ context: ServiceContext) -> String {
        let device = context.settings.homeAssistantUSBDevice
            .trimmingCharacters(in: .whitespaces)
        guard !device.isEmpty else { return "" }
        return "\n    devices:\n      - \(device):\(device)"
    }

    /// First-install settings without the web server block
    public static let initialConfiguration = """
        # Loads the default set of integrations.
        default_config:

        frontend:
          themes: !include_dir_merge_named themes

        automation: !include automations.yaml
        script: !include scripts.yaml
        scene: !include scenes.yaml
        """

    /// Web server settings: only local Caddy may proxy
    public static let initialHTTPStore = """
        {
          "version": 2,
          "minor_version": 2,
          "key": "http",
          "data": {
            "stable": {
              "server_port": 8123,
              "server_host": [
                "127.0.0.1"
              ],
              "use_x_forwarded_for": true,
              "trusted_proxies": [
                "127.0.0.1/32"
              ],
              "cors_allowed_origins": [
                "https://cast.home-assistant.io"
              ],
              "login_attempts_threshold": -1,
              "ip_ban_enabled": true,
              "ssl_profile": "modern",
              "use_x_frame_options": true,
              "created_at": "2026-09-24T00:00:00+00:00",
              "error": null,
              "error_message": null
            },
            "pending": null,
            "yaml_migration_done": true
          }
        }
        """

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.homeAssistantPath
        let config = "\(path)/config"
        return [
            #"""
            log "Home Assistant: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 700 \#(config)
            install -d -m 755 \#(config)/themes
            if [ ! -f \#(config)/configuration.yaml ]; then
              cat > \#(config)/configuration.yaml <<'EOF_HA_CONFIG'
            \#(Self.initialConfiguration)
            EOF_HA_CONFIG
            fi
            install -d -m 700 \#(config)/.storage
            if [ ! -f \#(config)/.storage/http ]; then
              cat > \#(config)/.storage/http <<'EOF_HA_HTTP'
            \#(Self.initialHTTPStore)
            EOF_HA_HTTP
              chmod 600 \#(config)/.storage/http
            fi
            [ -f \#(config)/automations.yaml ] || echo '[]' > \#(config)/automations.yaml
            [ -f \#(config)/scenes.yaml ] || echo '[]' > \#(config)/scenes.yaml
            [ -f \#(config)/scripts.yaml ] || : > \#(config)/scripts.yaml
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
        echo "Home Assistant: https://\#(hostname(context))"
        echo "  \#(L10nServices.homeAssistantOwnerWarning(lang))"
        echo "  \#(L10nServices.homeAssistantAppHint(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.homeAssistantPath
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
                    sizePaths: ["\(path)/config"]
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
            configDirectory: context.settings.homeAssistantPath,
            dataPaths: ["\(context.settings.homeAssistantPath)/config.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

public struct OpenClawService: ManagedService {
    public static let composeProject = "openclaw"
    public static let container = "openclaw"
    /// Next free loopback port in the catalog's block
    public static let webUIPort = 8102
    public static let gatewayPort = 18789
    public static let wrapperTarget = ServiceID.openclaw.rawValue
    public static let image = "ghcr.io/openclaw/openclaw:2026.9.2"

    /// Loopback only; each install adds the shared network's gateway
    public static let seededConfig =
        #"{"gateway":{"mode":"local","trustedProxies":["127.0.0.1","::1"]}}"#

    /// Where that file lives
    public static func configPath(_ context: ServiceContext) -> String {
        "\(context.settings.openclawPath)/state/openclaw.json"
    }

    /// Trusts the shared network's gateway, where Caddy arrives from
    static func trustGatewaySection(_ context: ServiceContext) -> String {
        let config = configPath(context)
        return #"""
        # Only that address: a home client in 192.168 is no proxy.
        gateway=$(docker network inspect \#(AIServicesNetwork.name) --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 '\.' || true)
        if [ -n "$gateway" ] && jq --arg g "$gateway" '.gateway.trustedProxies = ["127.0.0.1", "::1", $g]' '\#(config)' > '\#(config).new'; then
          mv '\#(config).new' '\#(config)'
        else
          rm -f '\#(config).new'
        fi
        """#
    }

    public let id = ServiceID.openclaw
    public let displayName = "OpenClaw"
    public let systemImage = "message.and.waveform"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// A Node process holding one session per paired messenger
    public let resources = ServiceResources(memoryMB: 1024, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.openclawHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.openclaw, context) : custom
    }

    public func modelEndpoint(_ context: ServiceContext) -> String? {
        if context.installedServices.contains(.liteLLM) {
            return AIServicesNetwork.url(LiteLLMService.container, LiteLLMService.containerPort) + "/v1"
        }
        if context.installedServices.contains(.ollama) {
            return AIServicesNetwork.url(OllamaService.container, OllamaService.apiPort)
        }
        return nil
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.openclawPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              openclaw:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                # PID 1 that reaps: this process spawns browsers and helpers,
                # and upstream's own compose asks for the same.
                init: true
                # Upstream's own posture, kept rather than trimmed: a service
                # that talks to strangers' messengers has no use for raw
                # sockets or for interface administration inside its namespace.
                cap_drop:
                  - NET_RAW
                  - NET_ADMIN
                security_opt:
                  - no-new-privileges:true
                environment:
                  # Guards the gateway and its web UI. Generated on the server
                  # — see the report for where to read it.
                  OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
                  OPENCLAW_GATEWAY_PORT: "\(Self.gatewayPort)"
                  OPENCLAW_STATE_DIR: /home/node/.openclaw
                  OPENCLAW_CONFIG_DIR: /home/node/.openclaw
                  OPENCLAW_CONFIG_PATH: /home/node/.openclaw/openclaw.json
                  OPENCLAW_WORKSPACE_DIR: /home/node/.openclaw/workspace
                volumes:
                  # One mount, because the workspace above lives inside the
                  # state directory: two mounts of nested paths would be two
                  # things to keep in step for no second lifetime.
                  - \(path)/state:/home/node/.openclaw
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.gatewayPort)"
                command:
                  - node
                  - dist/index.js
                  - gateway
                  - --bind
                  - lan
                  - --port
                  - "\(Self.gatewayPort)"\(AIServicesNetwork.composeTail)
            """,
            envTemplate: """
            OPENCLAW_GATEWAY_TOKEN=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.openclawPath
        return [
            #"""
            log "OpenClaw: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)
            # The image runs as uid 1000 and does not chown its own mount.
            # 700, not 755: paired messenger sessions live in here.
            install -d -m 700 -o 1000 -g 1000 \#(path)/state
            # Seeded ONCE and never rewritten. The gateway writes its own
            # settings back into this same file — the paired messengers, the
            # model, the channels — so a re-install that rewrote it would
            # undo the pairings a person made by scanning a QR code.
            if [ ! -s '\#(Self.configPath(context))' ]; then
              printf '%s\n' '\#(Self.seededConfig)' > '\#(Self.configPath(context))'
            fi
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            \#(AIServicesNetwork.createStep)
            \#(Self.trustGatewaySection(context))
            # Applied on every run, not only on the one that created it: the
            # container has to write this file back, and a restore can leave
            # it owned by root — the same reason AnythingLLM's settings file
            # is chowned outside its own seeding block.
            chown 1000:1000 '\#(Self.configPath(context))'
            chmod 600 '\#(Self.configPath(context))'
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort,
                   overwriteForwardedFor: true)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let path = context.settings.openclawPath
        var lines = [
            #"echo "OpenClaw:     https://\#(hostname(context))""#,
            #"echo "  \#(L10nServices.openclawTokenNote(lang)): $(grep '^OPENCLAW_GATEWAY_TOKEN=' \#(path)/.env | cut -d= -f2-)""#,
            #"echo "  \#(L10nServices.openclawPairingNote(lang))""#
        ]
        if let endpoint = modelEndpoint(context) {
            lines.append(#"echo "  \#(L10nServices.openclawModelNote(lang)): \#(endpoint)""#)
        } else {
            lines.append(#"echo "  \#(L10nServices.openclawNoModelNote(lang))""#)
        }
        return [lines.joined(separator: "\n")]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.openclawPath
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
                    dataPath: "\(path)/state",
                    databases: [],
                    quiesceServices: [Self.container],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/state"]
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
            configDirectory: context.settings.openclawPath,
            dataPaths: ["\(context.settings.openclawPath)/state.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}

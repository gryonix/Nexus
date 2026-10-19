public struct CloudflaredService: ManagedService {
    public static let composeProject = "cloudflared"
    public static let container = "cloudflared"
    public static let wrapperTarget = ServiceID.cloudflared.rawValue
    /// Exact pinned image tag
    public static let image = "cloudflare/cloudflared:2026.8.2"

    public let id = ServiceID.cloudflared
    public let displayName = "Cloudflare Tunnel"
    public let systemImage = "cloud"
    public let category = ServiceCategory.remoteAccess
    public let usesSharedAdminLogin = false
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// A single Go connector
    public let resources = ServiceResources(memoryMB: 128, diskGB: 1)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String { "" }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        ComposeFile(
            directory: context.settings.cloudflaredPath,
            composeContents: """
            services:
              cloudflared:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                # The host's own network, so the tunnel can reach Caddy on
                # 127.0.0.1 exactly as the dashboard's routes name it. A
                # bridge would put the connector on a different loopback and
                # every route would have to name a container address instead.
                network_mode: host
                command: tunnel --no-autoupdate run
                environment:
                  # Read from .env, which is 0600 and generated once. The token
                  # IS the credential for the whole tunnel.
                  TUNNEL_TOKEN: ${TUNNEL_TOKEN}
            """,
            envTemplate: """
            TUNNEL_TOKEN=
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.cloudflaredPath
        let lang = context.language
        return [
            #"""
            log "Cloudflare Tunnel: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            # A tunnel without its token retries for ever and says the same
            # thing every time, so the state is named ONCE here instead of
            # being left to be discovered in the container's log.
            if ! grep -q '^TUNNEL_TOKEN=.\+' \#(path)/.env 2>/dev/null; then
              log "\#(L10nServices.cloudflaredNoTokenNote(lang))"
            else
              docker compose -p \#(Self.composeProject) up -d
            fi
            """#
        ]
    }

    /// None, and that is the feature
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.cloudflaredPath
        let lang = context.language
        return [#"""
        echo "Cloudflare Tunnel:"
        echo "  \#(L10nServices.cloudflaredTokenNote(lang)): \#(path)/.env"
        echo "  \#(L10nServices.cloudflaredRoutesNote(lang)): https://127.0.0.1:443"
        echo "  \#(L10nServices.cloudflaredNoPortsNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(
            statusProbe: .container(
                name: Self.container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.container, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.container, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.container, "stop", timeoutClass: .restart)
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.cloudflaredPath,
            dataPaths: [],
            backupDirs: []
        )
    }
}

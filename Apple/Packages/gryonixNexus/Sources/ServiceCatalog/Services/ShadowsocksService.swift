public struct ShadowsocksService: ManagedService {
    public static let composeProject = "shadowsocks"
    public static let containerName = "shadowsocks"
    public static let method = "2022-blake3-aes-256-gcm"
    public static let image = "ghcr.io/shadowsocks/ssserver-rust:v1.24.0"
    public static let containerConfigPath = "/etc/shadowsocks-rust/config.json"

    public let id = ServiceID.shadowsocks
    public let displayName = "Shadowsocks"
    public let systemImage = "bolt.horizontal.circle"
    public let category = ServiceCategory.vpn
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.vpnHostname
        return custom.isEmpty ? "vpn.\(context.domain)" : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.shadowsocksPath
        let port = context.settings.shadowsocksPort
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              ssserver:
                image: \(Self.image)
                container_name: \(Self.containerName)
                restart: unless-stopped
                # Explicit binary name: the image's entrypoint does not prepend
                # `ssserver` for a bare `-c …`, so `exec "$@"` chokes on the
                # leading option ("exec: illegal option -c"). Run as root (0:0):
                # config.json is chmod 600 root-owned (setup and the panel both
                # keep it 600), so a non-root process could not read it.
                command: ssserver -c \(Self.containerConfigPath)
                user: "0:0"
                volumes:
                  - \(path)/config.json:\(Self.containerConfigPath):ro
                ports:
                  - "\(port):\(port)/tcp"
                  - "\(port):\(port)/udp"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.shadowsocksPath
        let port = context.settings.shadowsocksPort
        let lang = context.language
        return [#"""
        log "Shadowsocks: \#(L10nServices.serviceStarting(lang))"
        install -d \#(path)
        cd \#(path)
        # First run only: generate the pre-shared key on this server (a
        # base64-encoded 32-byte key for the 2022 cipher); re-runs keep it.
        if [ ! -f config.json ]; then
          SS_PASSWORD="$(openssl rand -base64 32)"
          cat > config.json <<EOF_SS_CONFIG
        {
            "server": "0.0.0.0",
            "server_port": \#(port),
            "password": "${SS_PASSWORD}",
            "method": "\#(Self.method)",
            "mode": "tcp_and_udp",
            "timeout": 300
        }
        EOF_SS_CONFIG
        fi
        chmod 600 config.json
        docker compose -p \#(Self.composeProject) pull -q
        docker compose -p \#(Self.composeProject) up -d
        """#]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        let port = context.settings.shadowsocksPort
        return [
            FirewallPort(port, .tcp, comment: "Shadowsocks"),
            FirewallPort(port, .udp, comment: "Shadowsocks")
        ]
    }

    /// Not an HTTP service — no reverse proxy
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.shadowsocksPath
        let port = context.settings.shadowsocksPort
        let lang = context.language
        let endpoint = "\(hostname(context)):\(port)"
        return [#"""
        echo "Shadowsocks: \#(endpoint) (TCP+UDP)"
        SS_PW="$(sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \#(path)/config.json | head -n 1)"
        SS_ENC="$(printf '%s' "$SS_PW" | sed -e 's/+/%2B/g' -e 's#/#%2F#g' -e 's/=/%3D/g')"
        echo "  \#(L10nServices.shadowsocksLinkLabel(lang)):"
        echo "  ss://\#(Self.method):${SS_ENC}@\#(endpoint)#gryonixNexus"
        echo "  \#(L10nServices.shadowsocksClientsNote(lang))"
        echo "  \#(L10nServices.adminViaWireGuardNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        return ServiceActions(
            statusProbe: .container(
                name: Self.containerName,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.containerName, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.containerName, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.containerName, "stop", timeoutClass: .restart),
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }
}

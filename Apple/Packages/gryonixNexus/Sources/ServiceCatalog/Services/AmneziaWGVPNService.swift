public struct AmneziaWGVPNService: ManagedService {
    public static let composeProject = "awgvpn"
    public static let containerName = "awgvpn"
    public static let webUIPort = 51823
    public static let image = "ghcr.io/deckersu/amnezia-wg-easy:14"

    public let id = ServiceID.amneziaWG
    public let displayName = "AmneziaWG"
    public let systemImage = "shield.lefthalf.filled.badge.checkmark"
    public let category = ServiceCategory.vpn
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.vpnHostname
        return custom.isEmpty ? "vpn.\(context.domain)" : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.amneziaWGPath
        let port = context.settings.amneziaWGPort
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              amnezia-wg-easy:
                image: \(Self.image)
                container_name: \(Self.containerName)
                restart: unless-stopped
                cap_add:
                  - NET_ADMIN
                  - SYS_MODULE
                # Most kernels have no AmneziaWG module, so awg-quick falls back
                # to the userspace amneziawg-go, which needs a TUN device to
                # bring wg0 up. Without it the container crashlooped with
                # "RTNETLINK: Not supported" / "Protocol not supported".
                devices:
                  - /dev/net/tun:/dev/net/tun
                sysctls:
                  - net.ipv4.ip_forward=1
                  - net.ipv4.conf.all.src_valid_mark=1
                environment:
                  WG_HOST: \(hostname(context))
                  WG_PORT: "\(port)"
                  # 10.10.0.x: clear of the relay tunnel (10.8.0.0/24) and the
                  # plain WireGuard VPN (10.9.0.0/24).
                  WG_DEFAULT_ADDRESS: 10.10.0.x
                  PASSWORD_HASH: ${PASSWORD_HASH}
                  PORT: "\(Self.webUIPort)"
                volumes:
                  # The deckersu fork stores its config under
                  # /etc/amnezia/amneziawg (NOT wg-easy's /etc/wireguard) — the
                  # container ENOENT-crashlooped saving wg0.json when mounted at
                  # the wrong path, and the panel (which reads <path>/data/
                  # wg0.json) saw nothing. Mount at the path the fork uses.
                  - \(path)/data:/etc/amnezia/amneziawg
                ports:
                  # The wg-easy fork sets the wg0 interface's ListenPort to
                  # WG_PORT (the same value advertised to clients), so the
                  # container listens on `port` INTERNALLY — not on a fixed
                  # 51820. Publishing host:port onto a different container port
                  # (the old 51820) sent every UDP packet to a port nothing
                  # listened on: clients handshook into a black hole. The
                  # container port must equal WG_PORT. (The unified VPN panel's
                  # own wgpanel already does this right — host:wgPort→wgPort.)
                  - "\(port):\(port)/udp"
                  - "127.0.0.1:\(Self.webUIPort):\(Self.webUIPort)"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.amneziaWGPath
        let lang = context.language
        return [#"""
        log "AmneziaWG VPN: \#(L10nServices.serviceStarting(lang))"
        install -d \#(path)
        cd \#(path)
        # First run only: generate the panel password on this server and hash
        # it with the image's node and bcryptjs; it goes in on stdin.
        if [ ! -f .env ]; then
          AWGVPN_PASSWORD="$(openssl rand -hex 12)"
          timeout 300 docker pull -q \#(Self.image) >/dev/null || true
          AWGVPN_OUT="$(printf '%s' "$AWGVPN_PASSWORD" | timeout 60 docker run --rm -i --entrypoint node \#(Self.image) -e 'let p="";process.stdin.on("data",d=>p+=d).on("end",()=>console.log(require("bcryptjs").hashSync(p,12)))' 2>/dev/null)" || AWGVPN_OUT=""
          AWGVPN_HASH="$(printf '%s' "$AWGVPN_OUT" | head -n1 | tr -d "'")"
          case "$AWGVPN_HASH" in '$2'*) ;; *) AWGVPN_HASH="" ;; esac
          if [ -n "$AWGVPN_HASH" ]; then
            printf 'ADMIN_PASSWORD=%s\nPASSWORD_HASH=%s\n' "$AWGVPN_PASSWORD" "$AWGVPN_HASH" > .env
          else
            # No hash: the stock panel starts without a password. It binds
            # loopback only and nothing proxies it — clients are managed from
            # the unified VPN panel — so this is a degraded but working VPN,
            # which beats an installation that never finishes.
            log "\#(L10nServices.amneziaPanelWithoutPassword(lang))"
            printf 'ADMIN_PASSWORD=%s\nPASSWORD_HASH=\n' "$AWGVPN_PASSWORD" > .env
          fi
        fi
        # docker compose interpolates $ inside .env values, so the bcrypt
        # hash must carry $$ or it reaches the container mangled (the WARN
        # "variable is not set" flood). Idempotent: runs of $ collapse to $$,
        # an already escaped hash is left as is; also repairs pre-fix installs.
        sed -i '/^PASSWORD_HASH=/s/\$\{1,\}/$$/g' .env
        chmod 600 .env
        docker compose -p \#(Self.composeProject) pull -q
        docker compose -p \#(Self.composeProject) up -d
        """#]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(context.settings.amneziaWGPort, .udp, comment: "AmneziaWG VPN")]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let port = VPNPortShare.clientPort(context)
        return [#"""
        echo "AmneziaWG: \#(hostname(context)):\#(port) (UDP)"
        echo "  \#(L10nServices.amneziaAdminViaWireGuardNote(context.language))"
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

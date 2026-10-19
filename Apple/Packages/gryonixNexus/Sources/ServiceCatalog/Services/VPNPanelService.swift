public struct VPNPanelService: ManagedService {
    public static let composeProject = "vpnpanel"
    public static let containerName = "vpnpanel"
    public static let path = "/opt/gryonix-vpn-panel"
    /// Loopback port the panel binds; the shared Caddy reverse-proxies vpn.<domain>
    public static let webUIPort = 51900
    public static let image = "gryonix-vpn-panel:local"
    public static let wgSubnet = "10.9.0.0/24"
    public static let adminGuardPath = "/etc/caddy/gryonixnexus-admin-guard"
    public static let lockdownScriptPath = "/opt/gryonixnexus-admin-lockdown.sh"
    public static let wrapperTarget = ServiceID.vpnPanel.rawValue

    public let id = ServiceID.vpnPanel
    public let displayName = "VPN Panel"
    public let systemImage = "shield.checkerboard"
    public let category = ServiceCategory.implicit
    /// The VPN protocols brought it — see `ManagedService.displayCategory`
    public let displayCategory = ServiceCategory.vpn
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.vpnHostname
        return custom.isEmpty ? "vpn.\(context.domain)" : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let wgPort = context.settings.wireguardVPNPort
        return ComposeFile(
            directory: Self.path,
            composeContents: """
            services:
              vpnpanel:
                build: \(Self.path)/build
                image: \(Self.image)
                container_name: \(Self.containerName)
                restart: unless-stopped
                cap_add:
                  - NET_ADMIN
                  - SYS_MODULE
                sysctls:
                  - net.ipv4.ip_forward=1
                env_file:
                  - \(Self.path)/.env
                volumes:
                  - \(Self.path)/data:/data
                  # The agent's broker restarts and inspects the protocol
                  # containers; the panel holds no docker socket. Config
                  # dirs below; unused mounts are harmless empty dirs.
                  - /run/gryonixnexus-panel:/run/gryonixnexus-panel
                  - \(context.settings.shadowsocksPath):/protocols/shadowsocks
                  - \(context.settings.xrayRealityPath):/protocols/xray
                  - \(context.settings.openVPNPath)/data:/protocols/openvpn
                  - \(context.settings.amneziaWGPath)/data:/protocols/amneziawg
                  # Read-only: lets the panel find mailcow's database
                  # credentials so it can offer the existing mailboxes as the
                  # sender for password-reset mail. The DIRECTORY is
                  # mounted, not mailcow.conf itself — docker materialises a
                  # missing bind source, and an empty mailcow.conf directory
                  # would make mailcow's own "already configured?" guard skip
                  # generate_config.sh on a later install. An empty directory
                  # is harmless: git clone still populates it.
                  - \(context.settings.mailcowPath):/protocols/mailcow:ro
                extra_hosts:
                  # Reaching the host's SMTP listener (mailcow's Postfix) from
                  # inside the container.
                  - "host.docker.internal:host-gateway"
                ports:
                  - "127.0.0.1:\(Self.webUIPort):80"
                  # WireGuard (only listens when WireGuard is among the enabled
                  # protocols; harmless otherwise).
                  - "\(wgPort):\(wgPort)/udp"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let host = hostname(context)
        let wgPort = context.settings.wireguardVPNPort
        let adminUser = ShellQuoting.singleQuoted(context.settings.adminUsername)
        let pwResolution = #"""
            VPNPANEL_PW=""
            if [ -f \#(Self.path)/.env ]; then
            VPNPANEL_PW="$(grep '^ADMIN_PASSWORD=' \#(Self.path)/.env | cut -d= -f2-)"
            fi
            case "$VPNPANEL_PW" in
              *[!0-9a-f]* | "") VPNPANEL_PW="$(openssl rand -hex 12)" ;;
              *) [ ${#VPNPANEL_PW} -eq 24 ] || VPNPANEL_PW="$(openssl rand -hex 12)" ;;
            esac
            """#
        return [#"""
        log "VPN Panel: \#(L10nServices.serviceStarting(lang))"
        install -d \#(Self.path)/build \#(Self.path)/data
        cat > \#(Self.path)/build/Dockerfile <<'EOF_VPNPANEL_DOCKER'
        \#(VPNPanelAssets.dockerfile)
        EOF_VPNPANEL_DOCKER
        cat > \#(Self.path)/build/app.py <<'EOF_VPNPANEL_APP'
        \#(VPNPanelAssets.appPY)
        EOF_VPNPANEL_APP
        cat > \#(Self.path)/build/index.html <<'EOF_VPNPANEL_HTML'
        \#(VPNPanelAssets.indexHTML)
        EOF_VPNPANEL_HTML
        cat > \#(Self.path)/build/login.html <<'EOF_VPNPANEL_LOGIN'
        \#(VPNPanelAssets.loginHTML)
        EOF_VPNPANEL_LOGIN
        cat > \#(Self.path)/build/reset.html <<'EOF_VPNPANEL_RESET'
        \#(VPNPanelAssets.resetHTML)
        EOF_VPNPANEL_RESET
        # Panel credentials in .env, refreshed on every run (a user-chosen
        # password is applied idempotently; a generated one is preserved — see
        # $VPNPANEL_PW resolution above). ADMIN_USER and the WG parameters
        # always track the current configuration.
        \#(pwResolution)
        {
          printf 'ADMIN_USER=%s\n' \#(adminUser)
          printf 'ADMIN_PASSWORD=%s\n' "$VPNPANEL_PW"
          printf 'WG_HOST=%s\n' "\#(host)"
          printf 'WG_PORT=%s\n' "\#(wgPort)"
          printf 'WG_SUBNET=%s\n' "\#(Self.wgSubnet)"
        } > \#(Self.path)/.env
        chmod 600 \#(Self.path)/.env
        [ -f \#(Self.path)/data/services.json ] || echo '{"services":[]}' > \#(Self.path)/data/services.json
        # Admin lockdown plumbing: the guard snippet (created locked by
        # default on first install, via the wrapper's own "on" below;
        # re-runs keep whatever state the dashboard last set) and the
        # wrapper the dashboard calls over sudo. "On" allows only
        # private-range sources (loopback, RFC1918,
        # ULA): VPN clients reach Caddy MASQUERADEd from the protocol
        # containers, whose Docker bridge may sit in ANY private pool
        # (172.16/12 or 192.168/16 once the pools run out — pinning bridge
        # subnets 403'd VPN clients). The scenario B relay tunnel
        # (10.8.0.0/24) carries relayed PUBLIC traffic, so it is denied
        # explicitly before the private-range allow — EXCEPT the hairpin
        # source .254, which the VPS SNATs VPN-client traffic to so it can
        # be told apart from public visitors (both otherwise reach Caddy as
        # the same VPS tunnel address). See NftablesConfig hairpin_src.
        install -d /etc/caddy
        if [ -f \#(Self.adminGuardPath) ]; then
          GRYONIXNEXUS_GUARD_EXISTED=1
        else
          : > \#(Self.adminGuardPath)
          GRYONIXNEXUS_GUARD_EXISTED=0
        fi
        cat > \#(Self.lockdownScriptPath) <<'EOF_VPNPANEL_LOCKDOWN'
        #!/bin/bash
        # Managed by gryonixNexus — VPN-only access switch for admin web panels.
        # on = every site; only host... = just those sites (per-service
        # selection); off = public again. Every Caddy site imports the guard,
        # so a host matcher inside it narrows which vhosts actually block.
        set -euo pipefail
        GUARD=\#(Self.adminGuardPath)
        # Shown to blocked visitors so a locked panel is a clear "denied"
        # page, not an empty-bodied 403 that browsers render as a blank
        # white screen. It names WireGuard specifically: whoever reads this
        # page is most often already connected to the VPN — on AmneziaWG or
        # one of the proxy protocols, which do not carry admin traffic — so
        # "connect to the VPN" would be advice they already followed.
        # ASCII only and no quotes: it rides through a Caddyfile heredoc and
        # lands inside a double-quoted respond argument.
        DENY='Access denied. The admin panels are reachable only over the VPN. Connect to your VPN and try again.'
        reload_caddy() { systemctl reload caddy 2>/dev/null || systemctl restart caddy || true; }
        write_guard() {
          hosts="$1"
          # Scenario-A hairpin allow-source. VPN clients on the containerised
          # protocols (amneziaWG / OpenVPN / shadowsocks / xray) that open an
          # admin panel served on THIS host's own public IP loop back through
          # the protocol/host NAT and reach Caddy SNAT'd to that public IP — a
          # source private_ranges does not cover, so the guard used to 403 a
          # genuinely VPN-side client (only the panel's own WireGuard, which
          # arrives from a private address, got through). No off-box client can
          # forge our own public IP as its source — the TCP return path comes
          # straight back to us — so our own global addresses are a safe allow.
          # This is the scenario-A counterpart to the 10.8.0.254 relay hairpin.
          selfip=$(
            { ip -4 -o addr show scope global; ip -6 -o addr show scope global; } 2>/dev/null \
              | awk '{ split($4, a, "/"); ip = a[1]; print ip (index(ip, ":") ? "/128" : "/32") }' \
              | paste -sd' ' -
          )
          # Cloudflare Tunnel visitors come from loopback; its header marks them.
          {
            if [ -n "$hosts" ]; then
              printf '@gryonixnexus_relay {\n'
              printf '    host %s\n' "$hosts"
              printf '    remote_ip 10.8.0.0/24\n'
              printf '    not remote_ip 10.8.0.254/32\n'
              printf '}\n'
              printf 'respond @gryonixnexus_relay "%s" 403\n' "$DENY"
              printf '@gryonixnexus_public {\n'
              printf '    host %s\n' "$hosts"
              printf '    not remote_ip private_ranges %s\n' "$selfip"
              printf '}\n'
              printf 'respond @gryonixnexus_public "%s" 403\n' "$DENY"
              printf '@gryonixnexus_tunnel {\n'
              printf '    host %s\n' "$hosts"
              printf '    header Cf-Connecting-IP *\n'
              printf '}\n'
              printf 'respond @gryonixnexus_tunnel "%s" 403\n' "$DENY"
            else
              printf '@gryonixnexus_relay {\n'
              printf '    remote_ip 10.8.0.0/24\n'
              printf '    not remote_ip 10.8.0.254/32\n'
              printf '}\n'
              printf 'respond @gryonixnexus_relay "%s" 403\n' "$DENY"
              printf '@gryonixnexus_public not remote_ip private_ranges %s\n' "$selfip"
              printf 'respond @gryonixnexus_public "%s" 403\n' "$DENY"
              printf '@gryonixnexus_tunnel header Cf-Connecting-IP *\n'
              printf 'respond @gryonixnexus_tunnel "%s" 403\n' "$DENY"
            fi
          } > "$GUARD"
          reload_caddy
        }
        case "${1:-status}" in
          on)
            write_guard ""
            echo on ;;
          only)
            shift
            [ "$#" -ge 1 ] || { echo "usage: $0 only host..." >&2; exit 64; }
            for h in "$@"; do
              case "$h" in
                *[!A-Za-z0-9.-]*|"") echo "invalid host: $h" >&2; exit 64 ;;
              esac
            done
            write_guard "$*"
            echo "only $*" ;;
          off)
            : > "$GUARD"
            reload_caddy
            echo off ;;
          status)
            if [ ! -s "$GUARD" ]; then
              echo off
            elif grep -q 'host ' "$GUARD"; then
              echo "only $(grep -m1 'host ' "$GUARD" | sed 's/^ *host //')"
            else
              echo on
            fi ;;
          *)
            echo "usage: $0 on|off|only host...|status" >&2; exit 64 ;;
        esac
        EOF_VPNPANEL_LOCKDOWN
        chmod 750 \#(Self.lockdownScriptPath)
        # Ship locked by default instead of public: run the wrapper's own
        # "on" verb once, right here, the same action the dashboard's switch
        # takes later. Only on the FIRST install — a re-run must never
        # fight an owner who chose "off" from the dashboard since.
        [ "$GRYONIXNEXUS_GUARD_EXISTED" = 1 ] || \#(Self.lockdownScriptPath) on
        docker build -t \#(Self.image) \#(Self.path)/build
        # cd before compose: without it the panel would inherit the previous
        # section's directory and launch THAT service's compose file.
        cd \#(Self.path)
        docker compose -p \#(Self.composeProject) up -d
        """#]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        guard context.settings.vpnClientAccess.publishesPanelSite else { return nil }
        return WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort, adminGuard: true,
                           overwriteForwardedFor: true)
    }

    public func extraSudoers(_ context: ServiceContext) -> [PrivilegedCommand] {
        [PrivilegedCommand(binaryPath: Self.lockdownScriptPath, arguments: "")]
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        context.settings.vpnClientAccess.publishesPanelSite ? [hostname(context)] : []
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let passwordLabel = L10nServices.passwordGeneratedOnServerLabel(lang)
        return [#"""
        echo "VPN Panel: https://\#(hostname(context))"
        echo "  \#(L10nServices.adminPanelLabel(lang)): https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): $(grep '^ADMIN_USER=' \#(Self.path)/.env | cut -d= -f2-)"
        echo "  \#(passwordLabel): $(grep '^ADMIN_PASSWORD=' \#(Self.path)/.env | cut -d= -f2-)"
        echo "  \#(L10nServices.vpnClientsNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(
            statusProbe: .container(
                name: Self.containerName,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.containerName, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.containerName, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.containerName, "stop", timeoutClass: .restart),
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
                    dataPath: "\(Self.path)/data",
                    databases: [],
                    quiesceServices: [Self.containerName],
                    encryptsByDefault: true,
                    sizePaths: ["\(Self.path)/data"]
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
        .builtOnServer([Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: Self.path,
            dataPaths: ["\(Self.path)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)],
            preSteps: [
                "ip link delete wgpanel 2>/dev/null || true"
            ],
            postSteps: [
                "rm -f \(Self.lockdownScriptPath)",
                ": > \(Self.adminGuardPath) 2>/dev/null || true",
                "systemctl reload caddy 2>/dev/null || true"
            ]
        )
    }
}

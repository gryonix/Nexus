/// A whole-house audio hub (MPD, Spotify Connect, Snapcast, UPnP, Bluetooth), at home only.
public struct OdioService: ManagedService {
    public static let version = "2026.10.0b3"
    public static let installerURL =
        "https://github.com/b0bbywan/odios/releases/download/2026.10.0b3/install.sh"
    public static let installerSHA256 = "1f1aafe4ef853ae10c9f6f134f24988b2943b6d5c50c388f8177103045c0f569"
    public static let account = "odio"
    public static let webUIPort = 8018
    public static let localHostname = "odio.local"
    public static let controlPath = "/usr/local/sbin/gryonixnexus-odio-ctl"
    public static let authSnippetPath = "/etc/caddy/gryonixnexus-odio-auth"
    public static let shairportUnit = "shairport-sync.service"
    public static let userUnits = [
        "odio-api.service", "mpd.service", "mympd.service", "spotifyd.service",
        "snapclient.service", "upmpdcli.service", shairportUnit
    ]
    public static let leftoverPackages = "mpd, myMPD, Spotifyd, Snapcast, upmpdcli, BlueZ, PulseAudio, odio-api, odioctl"

    public let id = ServiceID.odio
    public let displayName = "Audio hub (odio)"
    public let systemImage = "hifispeaker.2"
    public let category = ServiceCategory.audio
    public let runtime = ServiceRuntime.systemd(unit: "odio-api")
    public let resources = ServiceResources(memoryMB: 512, diskGB: 3)
    public let requiresHomeMachine = true

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.odioHostname
        return custom.isEmpty ? Self.localHostname : custom
    }

    /// Root helper that drives the account's user units
    public static func controlScript() -> String {
        #"""
        #!/bin/bash
        set -eu
        user=\#(account)
        units="\#(userUnits.joined(separator: " "))"
        uid="$(id -u "$user")"
        as_user() { runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" "$@"; }
        each_unit() {
          for unit in $units; do
            if as_user systemctl --user cat "$unit" >/dev/null 2>&1; then
              as_user systemctl --user "$@" "$unit"
            fi
          done
        }
        case "${1:-}" in
          status) as_user systemctl --user show $units --property=Id,LoadState,ActiveState ;;
          logs) journalctl "_UID=$uid" -n 500 --no-pager -o short-iso ;;
          start|restart) each_unit "$1" ;;
          stop) each_unit stop; as_user systemctl --user stop mpd.socket || true ;;
          disable) each_unit disable --now; as_user systemctl --user disable --now mpd.socket || true ;;
          *) exit 2 ;;
        esac
        """#
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? { nil }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let path = context.settings.odioPath
        let keepsOwnAirPlay = context.installedServices.contains(.shairportSync)
        return [
            #"""
            log "Audio hub (odio): \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            odio_tmp="$(mktemp -d)"
            curl -fsSL -o "$odio_tmp/install.sh" '\#(Self.installerURL)'
            echo '\#(Self.installerSHA256)  '"$odio_tmp/install.sh" | sha256sum -c - >/dev/null \
              || fail "\#(L10nServices.odioInstallerChecksum(lang))"
            odio_airplay=Y
            if [ "\#(keepsOwnAirPlay ? "1" : "0")" = 1 ] || [ -f \#(context.settings.shairportPath)/docker-compose.yml ]; then
              odio_airplay=N
            fi
            printf 'APT::Get::Assume-Yes "true";\n' > "$odio_tmp/apt.conf"
            odio_mympd=Y
            if grep -qE '^ID=(debian|raspbian)$' /etc/os-release && [ "$(. /etc/os-release; echo "$VERSION_ID" | cut -d. -f1)" -lt 13 ] 2>/dev/null; then
              odio_mympd=N
              echo 'myMPD needs Debian 13 or newer; installing the hub without it'
            fi
            DEBIAN_FRONTEND=noninteractive apt-get install -yq python3-jinja2 python3-cryptography
            TARGET_USER=\#(Self.account) ODIOS_VERSION=\#(Self.version) INSTALL_BRANDING=N \
              INSTALL_SHAIRPORT_SYNC="$odio_airplay" INSTALL_MYMPD="$odio_mympd" APT_CONFIG="$odio_tmp/apt.conf" \
              DEBIAN_FRONTEND=noninteractive bash -s < "$odio_tmp/install.sh"
            rm -rf "$odio_tmp"
            odio_home="$(getent passwd \#(Self.account) | cut -d: -f6)"
            install -d -m 700 -o \#(Self.account) -g \#(Self.account) "$odio_home/.config/odio-api/conf.d"
            printf 'bind: lo\n' > "$odio_home/.config/odio-api/conf.d/20-gryonixnexus.yml"
            chown \#(Self.account):\#(Self.account) "$odio_home/.config/odio-api/conf.d/20-gryonixnexus.yml"
            cat > \#(Self.controlPath) <<'EOF_ODIO_CTL'
            \#(Self.controlScript())
            EOF_ODIO_CTL
            chmod 755 \#(Self.controlPath)
            if [ ! -f \#(path)/.env ]; then
              install -m 600 /dev/null \#(path)/.env
              printf 'ODIO_WEB_USER=\#(Self.account)\nODIO_WEB_PASSWORD=%s\n' "$(openssl rand -hex 12)" > \#(path)/.env
            fi
            . \#(path)/.env
            printf 'basic_auth {\n    %s %s\n}\nredir / /ui/\n' "$ODIO_WEB_USER" "$(caddy hash-password --plaintext "$ODIO_WEB_PASSWORD")" \
              > \#(Self.authSnippetPath)
            chmod 644 \#(Self.authSnippetPath)
            \#(Self.controlPath) restart
            """#
        ]
    }

    /// None: discovery stays on the home network
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort,
                   basicAuthSnippet: Self.authSnippetPath, homeOnly: isAtHome(context))
    }

    /// Whether the panel answers only on its .local name
    public func isAtHome(_ context: ServiceContext) -> Bool {
        hostname(context).hasSuffix(".local")
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        isAtHome(context) ? [] : [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let path = context.settings.odioPath
        return [#"""
        echo "Audio hub: https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): $(grep '^ODIO_WEB_USER=' \#(path)/.env | cut -d= -f2-)"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^ODIO_WEB_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let ctl = Self.controlPath
        return ServiceActions(
            statusProbe: .systemdUnits(
                list: PrivilegedCommand(binaryPath: ctl, arguments: "status"),
                journal: PrivilegedCommand(binaryPath: ctl, arguments: "logs")
            ),
            restart: ServicePower.helper(ctl, "restart"),
            start: ServicePower.helper(ctl, "start"),
            stop: ServicePower.helper(ctl, "stop")
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec { .ownUpdater }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        let lang = context.language
        return UninstallSpec(
            dataPaths: [context.settings.odioPath],
            preSteps: [
                "[ -x \(Self.controlPath) ] && \(Self.controlPath) disable || true",
                "rm -f \(Self.controlPath) \(Self.authSnippetPath)",
                "echo \"odio: \(L10nServices.odioLeftovers(lang, packages: Self.leftoverPackages, account: Self.account))\""
            ]
        )
    }
}

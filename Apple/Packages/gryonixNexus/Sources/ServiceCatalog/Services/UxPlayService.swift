/// An AirPlay screen on the TV the machine is connected to, at home only.
public struct UxPlayService: ManagedService {
    public static let unit = "gryonixnexus-uxplay"
    public static let unitPath = "/etc/systemd/system/gryonixnexus-uxplay.service"
    public static let package = "uxplay"
    public static let account = "uxplay"
    public static let defaultName = "gryonix TV"
    public static let portBase = 7200
    public static let videoSink = "kmssink"
    public static let audioSink = "alsasink"
    public static let supportPackages = [
        "gstreamer1.0-plugins-good", "gstreamer1.0-plugins-bad", "gstreamer1.0-libav",
        "gstreamer1.0-alsa", "avahi-daemon"
    ]

    public let id = ServiceID.uxplay
    public let displayName = "AirPlay screen"
    public let systemImage = "airplayvideo"
    public let category = ServiceCategory.audio
    public let runtime = ServiceRuntime.systemd(unit: Self.unit)
    public let resources = ServiceResources(memoryMB: 256, diskGB: 1)
    public let requiresHomeMachine = true

    public init() {}

    /// The name, safe inside a unit file
    public static func screenName(_ context: ServiceContext) -> String {
        let forbidden = Set("\"\\$`%".unicodeScalars)
        let kept = context.settings.uxplayName.unicodeScalars
            .filter { $0.value >= 0x20 && $0.value != 0x7f && !forbidden.contains($0) }
        let name = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultName : name
    }

    public static func unitFile(_ context: ServiceContext) -> String {
        """
        [Unit]
        Description=UxPlay AirPlay screen
        After=network-online.target avahi-daemon.service
        Wants=network-online.target avahi-daemon.service

        [Service]
        User=\(account)
        Group=\(account)
        ExecStart=/usr/bin/uxplay -n "\(screenName(context))" -nh -p \(portBase) -vs \(videoSink) -as \(audioSink)
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=multi-user.target
        """
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? { nil }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let packages = ([Self.package] + Self.supportPackages).joined(separator: " ")
        return [
            #"""
            log "AirPlay screen: \#(L10nServices.serviceStarting(context.language))"
            \#(Apt.quiet) install -yq \#(packages)
            id \#(Self.account) >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin \#(Self.account)
            for group in audio video render; do
              if getent group "$group" >/dev/null; then usermod -aG "$group" \#(Self.account); fi
            done
            cat > \#(Self.unitPath) <<'EOF_UXPLAY_UNIT'
            \#(Self.unitFile(context))
            EOF_UXPLAY_UNIT
            systemctl daemon-reload
            systemctl enable --now avahi-daemon.service
            systemctl enable \#(Self.unit).service
            systemctl restart \#(Self.unit).service
            """#
        ]
    }

    /// Home network only, never forwarded
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        let ports = Self.portBase...(Self.portBase + 2)
        let tcp = ports.map { FirewallPort($0, .tcp, comment: "AirPlay screen (home network)") }
        let udp = ports.map { FirewallPort($0, .udp, comment: "AirPlay screen (home network)") }
        return tcp + udp
    }

    /// None: a screen has no web page
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        return [#"""
        echo "AirPlay screen: \#(Self.screenName(context))"
        echo "  \#(L10nServices.airplayScreenHint(lang))"
        echo "  \#(L10nServices.airplayScreenDrmNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let unit = "\(Self.unit).service"
        return ServiceActions(
            statusProbe: .systemdUnits(
                list: PrivilegedCommand(binaryPath: "/usr/bin/systemctl",
                                        arguments: "show \(unit) --property=Id --property=LoadState --property=ActiveState"),
                journal: PrivilegedCommand(binaryPath: "/usr/bin/journalctl",
                                           arguments: "-u \(unit) -n 500 --no-pager -o short-iso")
            ),
            restart: ServicePower.systemctl("restart", unit),
            start: ServicePower.systemctl("start", unit),
            stop: ServicePower.systemctl("stop", unit)
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec { .ownUpdater }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(preSteps: [
            "systemctl disable --now \(Self.unit).service >/dev/null 2>&1 || true",
            "rm -f \(Self.unitPath)",
            "systemctl daemon-reload || true",
            "\(Apt.quiet) remove -yq \(Self.package) >/dev/null 2>&1 || true",
            "userdel \(Self.account) >/dev/null 2>&1 || true"
        ])
    }
}

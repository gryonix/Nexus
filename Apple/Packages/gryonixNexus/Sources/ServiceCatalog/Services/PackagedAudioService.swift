/// Audio services installed from Debian packages.
public struct PackagedAudioService: ManagedService {
    public static let markerDirectory = "/var/lib/gryonixnexus/packaged"
    static let btAgentUnit = "gryonixnexus-bt-agent"

    public let id: ServiceID
    public let displayName: String
    public let systemImage: String
    public let category = ServiceCategory.audio
    public let runtime: ServiceRuntime
    public let resources = ServiceResources(memoryMB: 128, diskGB: 1)
    public let requiresHomeMachine = true
    public let packages: [String]
    /// Removed on uninstall; shared helpers such as avahi stay
    public let ownPackages: [String]
    public let units: [String]
    public let ports: [FirewallPort]
    let extraSetup: String
    let extraRemoval: [String]

    init(_ id: ServiceID, _ displayName: String, image: String, packages: [String], own: [String],
         units: [String], ports: [FirewallPort] = [], extraSetup: String = "", extraRemoval: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.systemImage = image
        self.runtime = .systemd(unit: units[0])
        self.packages = packages
        self.ownPackages = own
        self.units = units
        self.ports = ports
        self.extraSetup = extraSetup
        self.extraRemoval = extraRemoval
    }

    public static let snapserver = PackagedAudioService(
        .snapserver, "Multi-room server (Snapcast)", image: "hifispeaker.2",
        packages: ["snapserver", "avahi-daemon"], own: ["snapserver"], units: ["snapserver"],
        ports: [1704, 1705, 1780].map { FirewallPort($0, .tcp, comment: "Snapcast (home network)") })

    public static let snapclient = PackagedAudioService(
        .snapclient, "Multi-room speaker (Snapcast)", image: "hifispeaker",
        packages: ["snapclient", "avahi-daemon"], own: ["snapclient"], units: ["snapclient"])

    public static let upmpdcli = PackagedAudioService(
        .upmpdcli, "DLNA speaker", image: "music.note.house",
        packages: ["mpd", "upmpdcli", "avahi-daemon"], own: ["upmpdcli"], units: ["mpd", "upmpdcli"],
        ports: [FirewallPort(1900, .udp, comment: "DLNA (home network)"),
                FirewallPort(49152, .tcp, comment: "DLNA (home network)"),
                FirewallPort(49153, .tcp, comment: "DLNA (home network)")])

    public static let bluealsa = PackagedAudioService(
        .bluealsa, "Bluetooth speaker", image: "wave.3.right",
        packages: ["bluez", "bluez-alsa-utils", "bluez-tools"], own: ["bluez-alsa-utils", "bluez-tools"],
        units: ["bluetooth", "bluealsa", "bluealsa-aplay", btAgentUnit],
        extraSetup: bluetoothSetup,
        extraRemoval: ["rm -f /etc/systemd/system/\(btAgentUnit).service",
                       "rm -rf /etc/systemd/system/bluealsa.service.d/gryonixnexus.conf"])

    public static let raspotify = PackagedAudioService(
        .raspotify, "Spotify Connect speaker", image: "dot.radiowaves.left.and.right",
        packages: ["ca-certificates", "curl"], own: ["raspotify"], units: ["raspotify"],
        extraSetup: spotifySetup)

    public static let mympd = PackagedAudioService(
        .mympd, "Music library (MPD + myMPD)", image: "music.note.list",
        packages: ["mpd", "avahi-daemon", "ca-certificates", "curl"], own: ["mympd"], units: ["mpd", "mympd"],
        ports: [FirewallPort(8019, .tcp, comment: "myMPD (home network)")],
        extraSetup: mympdSetup,
        extraRemoval: ["rm -rf /etc/systemd/system/mympd.service.d/gryonixnexus.conf"])

    public static let all = [snapserver, snapclient, upmpdcli, bluealsa, raspotify, mympd]

    /// System units other services share; removal leaves them running
    static let sharedUnits: Set<String> = ["mpd", "bluetooth"]

    static let mympdSetup = #"""
        case "$(dpkg --print-architecture)" in
          amd64) mympd_sha=bb839fe621bc9ab6a08fbf71b2db3d007555fdf5eaabe94c7b04e18b19ba027c ;;
          arm64) mympd_sha=c65e824ec01f4cdd8f298869a3368865fd6d6a10a7877225c860522032588853 ;;
          armhf) mympd_sha=7524caf1677d88f4f0dcb0c8248c14c3b7f8c49120db7c2ea559d76e915ca349 ;;
          *) echo "myMPD has no package for this processor" >&2; exit 1 ;;
        esac
        mympd_deb="/tmp/mympd_$(dpkg --print-architecture).deb"
        curl -fsSL -o "$mympd_deb" "https://github.com/b0bbywan/odio-mympd/releases/download/v26.1.2/mympd_26.1.2-1_$(dpkg --print-architecture).deb"
        echo "$mympd_sha  $mympd_deb" | sha256sum -c - >/dev/null
        install -d /etc/systemd/system/mympd.service.d
        printf '[Service]\nEnvironment=MYMPD_HTTP_PORT=8019\nEnvironment=MYMPD_SSL=false\n' > /etc/systemd/system/mympd.service.d/gryonixnexus.conf
        DEBIAN_FRONTEND=noninteractive apt-get install -yq "$mympd_deb"
        rm -f "$mympd_deb"
        for mympd_dir in /var/lib/mympd /var/lib/private/mympd; do
          if [ -d "$mympd_dir/config" ]; then echo 8019 > "$mympd_dir/config/http_port"; echo false > "$mympd_dir/config/ssl"; fi
        done

        """#

    static let spotifySetup = #"""
        case "$(dpkg --print-architecture)" in
          amd64) spotify_sha=7b228feb0623bf0f9b65904961ad3ad9df8e1f4b07a002ab2388e1ee9385eeed ;;
          arm64) spotify_sha=4d272678f475ad18961563951b6c36e5395c8a85b8d5607d1e3e9f94671108e2 ;;
          armhf) spotify_sha=47cc9b1d1e75e583a7eb45c2fa24b38cf6ed92f3231443d37f9b2477e32be59b ;;
          *) echo "Spotify Connect has no package for this processor" >&2; exit 1 ;;
        esac
        spotify_deb="/tmp/raspotify_$(dpkg --print-architecture).deb"
        curl -fsSL -o "$spotify_deb" "https://github.com/dtcooper/raspotify/releases/download/0.48.4/raspotify_0.48.4.librespot.v0.8.0-99b6088_$(dpkg --print-architecture).deb"
        echo "$spotify_sha  $spotify_deb" | sha256sum -c - >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -yq "$spotify_deb"
        rm -f "$spotify_deb"
        sed -i "s/^#\?LIBRESPOT_NAME=.*/LIBRESPOT_NAME=\"$(hostname)\"/" /etc/raspotify/conf

        """#

    static let bluetoothSetup = """
        install -d /etc/systemd/system/bluealsa.service.d
        cat > /etc/systemd/system/bluealsa.service.d/gryonixnexus.conf <<'EOF_BLUEALSA'
        [Service]
        ExecStart=
        ExecStart=/usr/bin/bluealsa -p a2dp-sink
        EOF_BLUEALSA
        cat > /etc/systemd/system/\(btAgentUnit).service <<'EOF_BT_AGENT'
        [Unit]
        Description=Bluetooth pairing without a PIN
        After=bluetooth.service
        Requires=bluetooth.service

        [Service]
        ExecStartPre=/usr/bin/bluetoothctl power on
        ExecStartPre=/usr/bin/bluetoothctl discoverable on
        ExecStartPre=/usr/bin/bluetoothctl pairable on
        ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput
        Restart=on-failure

        [Install]
        WantedBy=multi-user.target
        EOF_BT_AGENT
        if [ -f /etc/bluetooth/main.conf ]; then sed -i 's/^#\\?DiscoverableTimeout.*/DiscoverableTimeout = 0/' /etc/bluetooth/main.conf; fi

        """

    /// Install marker; preinstalled packages lack it
    public var marker: String { "\(Self.markerDirectory)/\(id.rawValue)" }

    var unitList: String { units.map { "\($0).service" }.joined(separator: " ") }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? { nil }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        [
            "log \"\(displayName): \(L10nServices.serviceStarting(context.language))\"\n"
            + "\(Apt.quiet) install -yq \(packages.joined(separator: " "))\n"
            + extraSetup
            + nameSetup(Self.speakerName(context.settings.speakerName))
            + "systemctl daemon-reload\n"
            + "systemctl enable \(unitList)\n"
            + "systemctl restart \(unitList)\n"
            + "install -d -m 755 \(Self.markerDirectory)\n"
            + "touch \(marker)"
        ]
    }

    /// Services whose name the phones see
    public static let named: Set<ServiceID> = [.raspotify, .bluealsa, .upmpdcli]

    /// The name without characters a script cannot carry
    public static func speakerName(_ asked: String) -> String {
        let forbidden = Set("\"\\$`%'/&|".unicodeScalars)
        let kept = asked.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f && !forbidden.contains($0) }
        let trimmed = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return String(trimmed.unicodeScalars.prefix(40)).trimmingCharacters(in: .whitespaces)
    }

    /// Script lines that give the speaker its name
    func nameSetup(_ name: String) -> String {
        guard !name.isEmpty else { return "" }
        switch id {
        case .raspotify:
            return "sed -i 's/^#\\?LIBRESPOT_NAME=.*/LIBRESPOT_NAME=\"\(name)\"/' /etc/raspotify/conf\n"
        case .bluealsa:
            return "if [ -f /etc/bluetooth/main.conf ]; then sed -i 's/^#\\?Name *=.*/Name = \(name)/' /etc/bluetooth/main.conf; fi\n"
                + "bluetoothctl system-alias '\(name)' >/dev/null 2>&1 || true\n"
        case .upmpdcli:
            return "touch /etc/upmpdcli.conf\nsed -i '/^#\\?friendlyname *=/d' /etc/upmpdcli.conf\n"
                + "echo 'friendlyname = \(name)' >> /etc/upmpdcli.conf\n"
        default:
            return ""
        }
    }

    /// Home network only, never forwarded
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { ports }

    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        ["echo \"\(displayName): \(L10nServices.packagedAudioReady(context.language))\""]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let journalUnits = units.map { "-u \($0).service" }.joined(separator: " ")
        return ServiceActions(
            statusProbe: .systemdUnits(
                list: PrivilegedCommand(binaryPath: "/usr/bin/systemctl",
                                        arguments: "show \(unitList) --property=Id --property=LoadState --property=ActiveState"),
                journal: PrivilegedCommand(binaryPath: "/usr/bin/journalctl",
                                           arguments: "\(journalUnits) -n 500 --no-pager -o short-iso")
            ),
            restart: ServicePower.systemctl("restart", unitList),
            start: ServicePower.systemctl("start", unitList),
            stop: ServicePower.systemctl("stop", unitList)
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec { .ownUpdater }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        let own = units.filter { !Self.sharedUnits.contains($0) }.map { "\($0).service" }.joined(separator: " ")
        return UninstallSpec(preSteps: ["systemctl disable --now \(own) >/dev/null 2>&1 || true"]
            + extraRemoval
            + ["systemctl daemon-reload || true",
               "\(Apt.quiet) remove -yq \(ownPackages.joined(separator: " ")) >/dev/null 2>&1 || true",
               "rm -f \(marker)"])
    }
}

/// An AirPlay speaker, at home only.
public struct ShairportSyncService: ManagedService {
    public static let composeProject = "shairport-sync"
    public static let container = "shairport-sync"
    public static let wrapperTarget = ServiceID.shairportSync.rawValue
    public static let imageName = "mikebrady/shairport-sync"
    public static let defaultName = "gryonix"
    public static let defaultOutput = "default"
    public static let airplay2 = "airplay2"
    public static let airplay1 = "airplay1"

    public let id = ServiceID.shairportSync
    public let displayName = "AirPlay speaker"
    public let systemImage = "airplayaudio"
    public let category = ServiceCategory.audio
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 128, diskGB: 1)
    public let requiresHomeMachine = true

    public init() {}

    /// "latest" is AirPlay 2, "classic" is AirPlay 1
    public static func image(_ context: ServiceContext) -> String {
        let tag = context.settings.shairportMode == airplay1 ? "classic" : "latest"
        return "\(imageName):\(tag)"
    }

    /// The name, safe for a command line
    public static func speakerName(_ context: ServiceContext) -> String {
        let forbidden = Set("\"\\$`".unicodeScalars)
        let kept = context.settings.shairportName.unicodeScalars
            .filter { $0.value >= 0x20 && $0.value != 0x7f && !forbidden.contains($0) }
        let name = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultName : name
    }

    /// An ALSA device name, plain characters only
    public static func outputDevice(_ context: ServiceContext) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:,._=-")
        let device = String(context.settings.shairportOutput.filter { allowed.contains($0) })
        return device.isEmpty ? defaultOutput : playable(device)
    }

    /// Pi HDMI cards play only through their hdmi name
    public static func playable(_ device: String) -> String {
        let raw = "hw:CARD=vc4hdmi"
        return device.hasPrefix(raw) ? "hdmi:" + device.dropFirst("hw:".count) : device
    }

    /// The folder the speaker's metadata pipe is shared in
    private static func metadataMount(_ context: ServiceContext) -> String {
        cecVolume(context).enabled ? "\n      - \(cecPipeDirectory):\(cecPipeDirectory)" : ""
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.shairportPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              shairport-sync:
                image: \(Self.image(context))
                container_name: \(Self.container)
                restart: unless-stopped
                # Finding the speaker and streaming to it use the host's network.
                network_mode: host
                devices:
                  - /dev/snd
                volumes:
                  - ./\(Self.configFile):/etc/shairport-sync.conf:ro\(Self.metadataMount(context))
                command: -a "\(Self.speakerName(context))" -o alsa -- -d \(Self.outputDevice(context))
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.shairportPath
        return [
            #"""
            log "AirPlay speaker: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)
            cd \#(path)
            cat > \#(Self.configFile) <<'EOF_SHAIRPORT_CONF'
            \#(Self.configContents(context))EOF_SHAIRPORT_CONF
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    /// Home network only, never forwarded
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        let tcp = [3689, 5000, 7000].map { FirewallPort($0, .tcp, comment: "AirPlay (home network)") }
        let udp = ([319, 320, 5353] + Array(6000...6009))
            .map { FirewallPort($0, .udp, comment: "AirPlay (home network)") }
        return tcp + udp
    }

    /// None: a speaker has no web page
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        return [#"""
        echo "AirPlay:      \#(Self.speakerName(context))"
        echo "  \#(L10nServices.airplaySpeakerHint(lang))"
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
        UpdateSpec(images: [Self.image(context)])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.shairportPath,
            dataPaths: [],
            backupDirs: []
        )
    }
}

public struct WireGuardVPNService: ManagedService {
    public let id = ServiceID.wireguardVPN
    public let displayName = "WireGuard"
    public let systemImage = "network.badge.shield.half.filled"
    public let category = ServiceCategory.vpn
    public let runtime = ServiceRuntime.docker(composeProject: VPNPanelService.composeProject)

    public init() {}

    /// The WireGuard server + client management run in the unified panel
    public func composeFile(_ context: ServiceContext) -> ComposeFile? { nil }
    public func setupSteps(_ context: ServiceContext) -> [String] { [] }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(context.settings.wireguardVPNPort, .udp, comment: "WireGuard VPN")]
    }

    /// The unified panel owns vpn.<domain> and the A record
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }
    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }
    public func reportSteps(_ context: ServiceContext) -> [String] { [] }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(
            statusProbe: .container(
                name: VPNPanelService.containerName,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServiceCommand(
                PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                  arguments: "restart \(VPNPanelService.containerName)"),
                timeoutClass: .restart
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        .builtOnServer([])
    }

    /// Lives entirely inside the panel — removing the panel removes it
    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec { UninstallSpec() }
}

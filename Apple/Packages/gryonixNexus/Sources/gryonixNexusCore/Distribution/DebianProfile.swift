import ServiceCatalog

/// Debian profile (11/12): apt, systemd, nftables
public struct DebianProfile: DistributionProfile {
    public let id: DistributionProfileID = .debian
    public let osReleaseID = "debian"
    public let displayName = "Debian"
    public let firewallTool: FirewallTool = .nftables

    public init() {}

    public func installCommand(for packages: [String]) -> String {
        "\(Apt.dropRetiredSources)\n" +
        "\(Apt.quiet) update -q\n" +
        "\(Apt.quiet) install -yq --no-install-recommends " +
        packages.joined(separator: " ")
    }

    public func serviceRestartCommand(_ service: String) -> String {
        "systemctl restart \(service)"
    }

    public func addRepositoryCommand(_ repository: PackageRepository) -> String {
        AptRepositoryCommand.render(repository)
    }
}

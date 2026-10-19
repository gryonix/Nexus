import ServiceCatalog

public struct UbuntuProfile: DistributionProfile {
    public let id: DistributionProfileID = .ubuntu
    public let osReleaseID = "ubuntu"
    public let displayName = "Ubuntu"
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

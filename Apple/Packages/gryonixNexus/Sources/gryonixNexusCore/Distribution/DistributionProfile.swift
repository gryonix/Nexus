import ServiceCatalog

/// Distribution profile identifier for serialization/selection in the UI
public enum DistributionProfileID: String, Sendable, Hashable, CaseIterable {
    case debian, ubuntu

    public func makeProfile() -> any DistributionProfile {
        switch self {
        case .debian: return DebianProfile()
        case .ubuntu: return UbuntuProfile()
        }
    }
}

public enum DistributionMatch {
    public static func accepts(expected: String, id: String, idLike: String) -> Bool {
        if id == expected { return true }
        let supported = Set(DistributionProfileID.allCases.map { $0.makeProfile().osReleaseID })
        if supported.contains(id) { return false }
        return idLike.split(separator: " ").contains { $0 == expected }
    }
}

/// Firewall tool
public enum FirewallTool: Sendable, Hashable {
    case nftables, ufw, iptables
}

/// A third-party package repository a service is installed from
public struct PackageRepository: Sendable, Hashable {
    /// Short identifier used for key/source file names (e.g
    public let name: String
    public let aptGPGKeyURL: String
    public let aptSourceListURL: String

    public init(name: String, aptGPGKeyURL: String, aptSourceListURL: String) {
        self.name = name
        self.aptGPGKeyURL = aptGPGKeyURL
        self.aptSourceListURL = aptSourceListURL
    }
}

enum AptRepositoryCommand {
    static func render(_ repository: PackageRepository) -> String {
        let keyring = "/usr/share/keyrings/\(repository.name)-archive-keyring.gpg"
        return """
        \(Apt.quiet) install -yq --no-install-recommends apt-transport-https curl gnupg
        curl -1sLf '\(repository.aptGPGKeyURL)' | gpg --dearmor --yes -o \(keyring)
        curl -1sLf '\(repository.aptSourceListURL)' > /etc/apt/sources.list.d/\(repository.name).list
        """
    }
}

public protocol DistributionProfile: Sendable {
    var id: DistributionProfileID { get }
    var osReleaseID: String { get }
    /// Human-readable name for error messages
    var displayName: String { get }
    var firewallTool: FirewallTool { get }
    func installCommand(for packages: [String]) -> String
    func serviceRestartCommand(_ service: String) -> String
    func addRepositoryCommand(_ repository: PackageRepository) -> String
}

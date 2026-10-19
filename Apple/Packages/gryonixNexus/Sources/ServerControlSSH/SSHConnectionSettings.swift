import Foundation
import ServerControl

/// Connection parameters for the Citadel-backed runner
public struct SSHConnectionSettings: Sendable {
    public var vpsHost: String
    public var vpsPort: Int
    public var username: String
    public var homeHost: String
    public var homePort: Int
    public var homeLANHost: String?
    public var privateKeySeed: Data
    public var passwords: [SSHHostID: String] = [:]
    public var pinnedVPSHostKey: String?
    public var pinnedHomeHostKey: String?

    public var bastion: Hop?

    public var entryFallback: Fallback?

    /// A machine dialled on the way to another
    public struct Hop: Sendable, Hashable {
        public let host: String
        public let port: Int
        public let username: String
        /// The key that signs in to THIS hop
        public let privateKeySeed: Data
        public let password: String?
        public let pinnedHostKey: String?

        public init(host: String, port: Int = 22, username: String,
                    privateKeySeed: Data, password: String? = nil,
                    pinnedHostKey: String? = nil) {
            self.host = host
            self.port = port
            self.username = username
            self.privateKeySeed = privateKeySeed
            self.password = password
            self.pinnedHostKey = pinnedHostKey
        }

        public var endpoint: String { "\(host):\(port)" }
    }

    public struct Fallback: Sendable, Hashable {
        public let host: String
        public let port: Int
        public let bastion: Hop?

        public init(host: String, port: Int, bastion: Hop? = nil) {
            self.host = host
            self.port = port
            self.bastion = bastion
        }
    }

    public var proxy: ProxyConnect.Endpoint?

    /// Machines beyond the two the fields above describe
    public var additionalNodes: [NodeAddress] = []

    /// Where one node lives and what reaches it
    public struct NodeAddress: Sendable, Hashable {
        public let id: UUID
        public let host: String
        public let port: Int
        /// The machine this one is reached THROUGH
        public let parent: SSHHostID?
        public let lanHost: String?
        public let pinnedHostKey: String?

        public init(id: UUID, host: String, port: Int = 22, parent: SSHHostID? = nil,
                    lanHost: String? = nil, pinnedHostKey: String? = nil) {
            self.id = id
            self.host = host
            self.port = port
            self.parent = parent
            self.lanHost = lanHost
            self.pinnedHostKey = pinnedHostKey
        }
    }

    public init(
        vpsHost: String,
        vpsPort: Int = 22,
        username: String,
        homeHost: String,
        homePort: Int = 22,
        homeLANHost: String? = nil,
        privateKeySeed: Data,
        passwords: [SSHHostID: String] = [:],
        pinnedVPSHostKey: String? = nil,
        pinnedHomeHostKey: String? = nil
    ) {
        self.vpsHost = vpsHost
        self.vpsPort = vpsPort
        self.username = username
        self.homeHost = homeHost
        self.homePort = homePort
        self.homeLANHost = homeLANHost
        self.privateKeySeed = privateKeySeed
        self.passwords = passwords
        self.pinnedVPSHostKey = pinnedVPSHostKey
        self.pinnedHomeHostKey = pinnedHomeHostKey
    }

    public static func additionalNodes(of deployment: Deployment,
                                pin: (SSHHostID) -> String?) -> [NodeAddress] {
        deployment.nodes.filter { $0.legacySlot == nil }.map { node in
            NodeAddress(
                id: node.id,
                host: node.endpoint.host,
                port: node.endpoint.port,
                parent: node.routedThrough.flatMap { parent in
                    deployment.nodes.first { $0.id == parent }?.sshHost
                },
                pinnedHostKey: pin(node.sshHost)
            )
        }
    }

    public static func make(config: DashboardConfig, identity: AppSSHIdentity,
                            passwords: [SSHHostID: String] = [:],
                            pinnedVPSHostKey: String? = nil,
                            pinnedHomeHostKey: String? = nil,
                            homeLANHost: String? = nil) -> SSHConnectionSettings {
        SSHConnectionSettings(
            vpsHost: config.vpsHost,
            vpsPort: config.sshPort,
            username: config.sshUser,
            homeHost: config.homeWGAddress,
            homePort: config.sshPort,
            homeLANHost: homeLANHost,
            privateKeySeed: identity.privateKeySeed,
            passwords: passwords,
            pinnedVPSHostKey: pinnedVPSHostKey,
            pinnedHomeHostKey: pinnedHomeHostKey
        )
    }
}

/// A server node: addressing + role + distribution profile.
public struct ServerNode: Sendable, Hashable {
    public let role: ServerRole
    public let publicAddress: NetworkAddress?    // nil for the home server
    public let vpnAddress: NetworkAddress?
    public let distribution: DistributionProfileID

    public init(
        role: ServerRole,
        publicAddress: NetworkAddress? = nil,
        vpnAddress: NetworkAddress? = nil,
        distribution: DistributionProfileID = .debian
    ) {
        self.role = role
        self.publicAddress = publicAddress
        self.vpnAddress = vpnAddress
        self.distribution = distribution
    }
}

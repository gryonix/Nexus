/// Whether a deployment's services run inside the house
public enum HomePlacement {
    /// Scenario B, LAN-only and dynamic DNS imply home
    public static func isAtHome(topology: Topology, scope: DeploymentScope,
                                machineAtHome: Bool) -> Bool {
        topology == .vpsRelayWithHomeBackend || impliesHome(scope) || machineAtHome
    }

    /// Scopes that only make sense for a machine at home
    public static func impliesHome(_ scope: DeploymentScope) -> Bool {
        scope == .localOnly || scope == .dynamicDNS
    }

    /// Whether the configurator must ask about the machine
    public static func needsAnswer(topology: Topology, scope: DeploymentScope) -> Bool {
        topology == .singleHost && !impliesHome(scope)
    }
}

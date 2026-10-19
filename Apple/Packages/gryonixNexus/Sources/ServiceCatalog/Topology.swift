/// Deployment topology — the two supported scenarios, kept extensible.
/// Lives in ServiceCatalog (the shared bottom layer) so both the generator
/// and the dashboard can reference it without depending on each other.
/// String raw values keep the on-disk JSON of saved deployments stable.
public enum Topology: String, Sendable, Hashable, Codable, CaseIterable {
    case singleHost                              // scenario A
    case vpsRelayWithHomeBackend                 // scenario B
}

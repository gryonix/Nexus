/// Server role within the topology.
public enum ServerRole: String, Sendable, Hashable, CaseIterable {
    case singleHost      // scenario A: single server with a public IP
    case vpsRelay        // scenario B: VPS — entry point/relay
    case homeBackend     // scenario B: home server with mail
}

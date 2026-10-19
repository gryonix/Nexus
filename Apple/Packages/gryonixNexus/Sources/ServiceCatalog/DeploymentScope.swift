public enum DeploymentScope: String, Sendable, Hashable, Codable, CaseIterable {
    /// Normal flow: a real domain, DNS records, automatic ACME certificates
    case publicInternet
    case localOnly
    case cloudflareTunnel

    case dynamicDNS

    case meshOnly

    /// Whether Caddy issues its own certificate instead of asking ACME
    public var usesInternalTLS: Bool {
        switch self {
        case .publicInternet, .dynamicDNS: return false
        case .localOnly, .cloudflareTunnel, .meshOnly: return true
        }
    }

    /// Whether the deployment publishes A records naming its own address
    public var publishesAddressRecords: Bool {
        switch self {
        case .publicInternet, .dynamicDNS: return true
        case .localOnly, .cloudflareTunnel, .meshOnly: return false
        }
    }

    public var carriesNonWebServices: Bool {
        switch self {
        case .publicInternet, .dynamicDNS: return true
        case .localOnly, .cloudflareTunnel, .meshOnly: return false
        }
    }

    /// Whether the server keeps its own DNS records current
    public var maintainsItsOwnDNSRecords: Bool { self == .dynamicDNS }

    public var requiresMesh: Bool { self == .meshOnly }
}

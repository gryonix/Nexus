public enum ModelBackend: String, Sendable, Hashable, Codable, CaseIterable {
    /// On this machine, in a local engine this catalog installs
    case here

    case home

    /// Nowhere here: the services call somebody else's API
    case external

    /// True when the deployment runs an engine of its own
    public var runsLocalEngine: Bool { self != .external }
}

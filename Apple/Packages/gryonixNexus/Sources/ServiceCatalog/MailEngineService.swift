/// A service that acts as the domain's mail engine (the MX target).
/// At most one engine may be selected — enforced by input validation.
/// Adding a new engine = one MailEngineService implementation + one
/// ServiceRegistry entry, like any other service.
public protocol MailEngineService: ManagedService {
    /// The mail hostname this engine mandates (e.g
    func requiredHostname(forDomain domain: String) -> String?
}

extension MailEngineService {
    public func requiredHostname(forDomain domain: String) -> String? { nil }

    public var requiresPublicDomain: Bool { true }
}

import ServiceCatalog

/// Unified validation error type for display in the UI
public enum ValidationError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidDomain(String)
    case invalidHostname(String)
    case invalidAddress(String)
    case missingPublicIP(role: ServerRole)
    case missingVPNAddress(role: ServerRole)
    case inconsistentTopology(String)

    public func message(_ language: AppLanguage) -> String {
        switch self {
        case .invalidDomain(let value):
            return L10nValidation.invalidDomain(language, value: value)
        case .invalidHostname(let value):
            return L10nValidation.invalidHostname(language, value: value)
        case .invalidAddress(let value):
            return L10nValidation.invalidAddress(language, value: value)
        case .missingPublicIP(let role):
            return L10nValidation.missingPublicIP(language, role: role.rawValue)
        case .missingVPNAddress(let role):
            return L10nValidation.missingVPNAddress(language, role: role.rawValue)
        case .inconsistentTopology(let reason):
            return reason
        }
    }

    public var description: String { message(.en) }
}

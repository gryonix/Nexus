/// Traffic-light style health of a probe, peer, or container.
/// Color mapping lives in the UI layer; the model only names the level
/// and the SF Symbol so logic stays platform-independent.
public enum HealthLevel: Sendable, Hashable {
    case ok
    case warning
    case critical
    case unknown

    public var systemImageName: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

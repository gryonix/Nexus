import Foundation

public extension SSHHostID {
    /// The disk spelling
    var persistedRaw: String {
        switch kind {
        case .slot(.vps): return "vps"
        case .slot(.home): return "home"
        case .node(let id): return "node:\(id.uuidString)"
        }
    }

    /// Decodes what `persistedRaw` wrote
    init(persistedRaw raw: String) {
        switch raw {
        case "home": self = .home
        case "vps": self = .vps
        default:
            if raw.hasPrefix("node:"), let id = UUID(uuidString: String(raw.dropFirst(5))) {
                self = .node(id)
            } else {
                self = .vps
            }
        }
    }
}

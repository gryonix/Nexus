import Foundation
import ServiceCatalog

public enum ConfigurationHandoff: Equatable, Sendable {
    /// Installable as a system VPN configuration through a `.mobileconfig`
    case configurationProfile
    /// Openable by whichever app claims the scheme
    case openIn(URL)
    case fileOnly
}

public enum VPNConfigurationHandoff {
    /// The link schemes the panel emits, per protocol
    private static func scheme(for protocolID: ServiceID) -> String? {
        switch protocolID {
        case .shadowsocks: return "ss"
        case .xrayReality: return "vless"
        default: return nil
        }
    }

    public static func route(protocolID: ServiceID,
                             text: String,
                             platform: VPNConfigurationProfile.Platform) -> ConfigurationHandoff {
        if let scheme = scheme(for: protocolID) {
            return link(in: text, scheme: scheme).map { .openIn($0.url) } ?? .fileOnly
        }
        guard VPNConfigurationProfile.isSupported(protocolID, on: platform) else { return .fileOnly }
        if protocolID == .openVPN, (try? OpenVPNProfileConfig(parsing: text)) == nil {
            return .fileOnly
        }
        return .configurationProfile
    }

    static func link(in text: String, scheme: String) -> (url: URL, rawText: String)? {
        let prefix = scheme + "://"
        guard let line = text
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix(prefix) })
        else { return nil }

        if let url = URL(string: line) { return (url, line) }
        guard let hash = line.firstIndex(of: "#") else { return nil }
        let label = String(line[line.index(after: hash)...])
        let encoded = label.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""
        guard let url = URL(string: String(line[..<hash]) + "#" + encoded) else { return nil }
        return (url, line)
    }
}

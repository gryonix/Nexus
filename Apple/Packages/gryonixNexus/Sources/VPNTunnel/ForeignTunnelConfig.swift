import Foundation
import ServiceCatalog
import VPNProfile

/// A configuration from a server the app does not manage
public enum ForeignTunnelConfig {
    /// The device id every imported tunnel carries
    public static let deviceID = "imported"

    public struct Detected: Equatable, Sendable {
        public let protocolID: ServiceID
        /// The configuration in the shape the tunnel reads
        public let text: String
        public let suggestedName: String
    }

    public enum Failure: Error, Equatable {
        case empty
        case notRecognised
        /// Read, but this build cannot bring it up
        case notCarried(ServiceID)
        case unreadable
    }

    public static func detect(_ input: String) throws -> Detected {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.empty }
        if let key = AmneziaKey.link(in: text) {
            let decoded = try AmneziaKey.decode(key)
            return try wireGuard(decoded.config, name: decoded.name)
        }
        if text.range(of: "[Interface]", options: .caseInsensitive) != nil {
            return try wireGuard(text, name: nil)
        }
        if let kind = ProxyLinkConfig.kind(of: text) {
            return try proxy(text, kind: kind)
        }
        if text.contains("\nremote ") || text.hasPrefix("client") || text.hasPrefix("remote ") {
            throw Failure.notCarried(.openVPN)
        }
        throw Failure.notRecognised
    }

    private static func wireGuard(_ text: String, name: String?) throws -> Detected {
        guard let config = try? WireGuardQuickConfig(parsing: text) else { throw Failure.unreadable }
        let protocolID: ServiceID = config.isObfuscated ? .amneziaWG : .wireguardVPN
        return Detected(protocolID: protocolID, text: config.rawText,
                        suggestedName: name.flatMap(nonEmpty) ?? config.name)
    }

    private static func proxy(_ text: String, kind: ProxyLinkConfig.Kind) throws -> Detected {
        guard let link = try? ProxyLinkConfig(parsing: text, kind: kind) else { throw Failure.unreadable }
        let protocolID: ServiceID = kind == .shadowsocks ? .shadowsocks : .xrayReality
        guard TunnelCapableProtocols.isIntegrated(protocolID) else { throw Failure.notCarried(protocolID) }
        return Detected(protocolID: protocolID, text: link.rawText,
                        suggestedName: fragment(of: link.rawText) ?? link.host)
    }

    /// The `#name` a share link ends with
    static func fragment(of link: String) -> String? {
        guard let hash = link.lastIndex(of: "#") else { return nil }
        let raw = String(link[link.index(after: hash)...])
        return nonEmpty(raw.removingPercentEncoding ?? raw)
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TunnelProfile {
    /// Imported from a configuration, with no server behind it here
    public var isForeign: Bool { deviceID == ForeignTunnelConfig.deviceID }
}

import Foundation

/// A tunnel's server reached by a remembered address
public struct EndpointPin: Codable, Equatable, Sendable {
    /// The domain the configuration names
    public let host: String
    /// The public address used instead of looking it up
    public let address: String

    public init(host: String, address: String) {
        self.host = host
        self.address = address
    }

    /// The endpoint with the address instead of a matching host
    public func replacingHost(of endpoint: String) -> String? {
        guard let parts = Self.split(endpoint),
              parts.host.caseInsensitiveCompare(host) == .orderedSame else { return nil }
        return Self.join(address, parts.port)
    }

    /// "host:port" or "[v6]:port" as host and port
    public static func split(_ endpoint: String) -> (host: String, port: String)? {
        let text = endpoint.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard rest.hasPrefix(":"), rest.count > 1, !host.isEmpty else { return nil }
            return (host, String(rest.dropFirst()))
        }
        guard let cut = text.lastIndex(of: ":"), text.firstIndex(of: ":") == cut else { return nil }
        let host = String(text[..<cut]), port = String(text[text.index(after: cut)...])
        return host.isEmpty || port.isEmpty ? nil : (host, port)
    }

    /// Joins host and port, bracketing an IPv6 host
    public static func join(_ host: String, _ port: String) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Whether the text is an IPv4 or IPv6 address
    public static func isAddress(_ text: String) -> Bool {
        ipv4Bytes(text) != nil || ipv6Bytes(text) != nil
    }

    /// Whether the address is reachable on the public internet
    public static func isPublic(_ address: String) -> Bool {
        if let bytes = ipv4Bytes(address) { return isPublicIPv4(bytes) }
        if let bytes = ipv6Bytes(address) { return isPublicIPv6(bytes) }
        return false
    }

    private static func isPublicIPv4(_ b: [UInt8]) -> Bool {
        switch (b[0], b[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (100, 64...127), (172, 16...31), (198, 18...19): return false
        case (224..., _): return false
        default: return true
        }
    }

    private static func isPublicIPv6(_ b: [UInt8]) -> Bool {
        if b.allSatisfy({ $0 == 0 }) || b == [UInt8](repeating: 0, count: 15) + [1] { return false }
        if b[0] & 0xFE == 0xFC || b[0] == 0xFF { return false }
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 { return false }
        return true
    }

    private static func ipv4Bytes(_ text: String) -> [UInt8]? {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func ipv6Bytes(_ text: String) -> [UInt8]? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}

extension EndpointPin {
    /// The pin a provider configuration carries, if any
    public init?(providerConfiguration: [String: Any]?) {
        guard let host = providerConfiguration?[VPNTunnelKeys.endpointPinHost] as? String,
              let address = providerConfiguration?[VPNTunnelKeys.endpointPinAddress] as? String,
              !host.isEmpty, Self.isPublic(address) else { return nil }
        self.init(host: host, address: address)
    }

    /// The entries that carry this pin to the tunnel
    public var providerEntries: [String: String] {
        [VPNTunnelKeys.endpointPinHost: host, VPNTunnelKeys.endpointPinAddress: address]
    }
}

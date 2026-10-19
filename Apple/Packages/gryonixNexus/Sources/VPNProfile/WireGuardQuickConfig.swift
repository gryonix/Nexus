import Foundation

/// A `wg-quick` configuration as the VPN panel exports it
public struct WireGuardQuickConfig: Equatable, Sendable {
    /// The exact `[Interface]`/`[Peer]` text
    public let rawText: String
    /// `host:port` from the peer's Endpoint — also the tunnel's server address
    public let endpoint: String
    /// A short label derived from the endpoint host
    public let name: String

    /// The interface's own addresses, e.g
    public let addresses: [String]
    public let dns: [String]
    public let mtu: Int?

    /// The peer's public key — what identifies the server end
    public let peerPublicKey: String?
    public let interfacePrivateKey: String?
    public let peerPresharedKey: String?
    public let allowedIPs: [String]
    public let persistentKeepalive: Int?

    public let obfuscation: [(key: String, value: String)]

    public var isObfuscated: Bool { !obfuscation.isEmpty }

    /// The nine keys AmneziaWG adds under `[Interface]`
    static let obfuscationKeys = ["Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"]

    public enum ParseError: Error, Equatable {
        case missingInterface, missingPeer, missingEndpoint, severalPeers
    }

    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = Self.sections(in: trimmed)
        guard let interface = sections.first(where: { $0.name == "interface" }) else {
            throw ParseError.missingInterface
        }
        let peers = sections.filter { $0.name == "peer" }
        guard let peer = peers.first else { throw ParseError.missingPeer }
        guard peers.count == 1 else { throw ParseError.severalPeers }
        guard let endpoint = peer.value(of: "Endpoint"), !endpoint.isEmpty else {
            throw ParseError.missingEndpoint
        }

        self.rawText = trimmed
        self.endpoint = endpoint
        self.name = Self.host(ofEndpoint: endpoint)

        self.addresses = Self.list(interface.allValues(of: "Address"))
        self.dns = Self.list(interface.allValues(of: "DNS"))
        self.mtu = interface.value(of: "MTU").flatMap(Int.init)
        self.peerPublicKey = peer.value(of: "PublicKey")
        self.interfacePrivateKey = interface.value(of: "PrivateKey")
        self.peerPresharedKey = peer.value(of: "PresharedKey")
        self.allowedIPs = Self.list(peer.allValues(of: "AllowedIPs"))
        self.persistentKeepalive = peer.value(of: "PersistentKeepalive").flatMap(Int.init)
        self.obfuscation = Self.obfuscationKeys.compactMap { key in
            interface.value(of: key).map { (key: key, value: $0) }
        }
    }

    public static func == (lhs: WireGuardQuickConfig, rhs: WireGuardQuickConfig) -> Bool {
        lhs.rawText == rhs.rawText
    }

    // MARK: - Parsing

    /// One `[Name]` block and its `Key = value` lines
    private struct Section {
        let name: String
        let lines: [String]

        /// Every line of this key, joined as one comma list
        func allValues(of key: String) -> String? {
            let found = lines.compactMap { Section(name: name, lines: [$0]).value(of: key) }
            return found.isEmpty ? nil : found.joined(separator: ",")
        }

        func value(of key: String) -> String? {
            for line in lines {
                let stripped = line.prefix { $0 != "#" }
                let parts = stripped.split(separator: "=", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces)
                        .caseInsensitiveCompare(key) == .orderedSame
                else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            return nil
        }
    }

    private static func sections(in text: String) -> [Section] {
        var sections: [Section] = []
        var name: String?
        var lines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                if let name { sections.append(Section(name: name, lines: lines)) }
                name = String(line.dropFirst().dropLast()).lowercased()
                lines = []
            } else if name != nil {
                lines.append(line)
            }
        }
        if let name { sections.append(Section(name: name, lines: lines)) }
        return sections
    }

    /// `10.9.0.4/32, fd00::4/128` — wg-quick's comma-separated lists
    private static func list(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func host(ofEndpoint endpoint: String) -> String {
        if endpoint.hasPrefix("["), let close = endpoint.firstIndex(of: "]") {
            return String(endpoint[endpoint.index(after: endpoint.startIndex)..<close])
        }
        guard let colon = endpoint.lastIndex(of: ":") else { return endpoint }
        return String(endpoint[endpoint.startIndex..<colon])
    }
}

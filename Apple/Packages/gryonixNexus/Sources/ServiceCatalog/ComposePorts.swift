import Foundation

public struct PublishedHostPort: Sendable, Hashable {
    public let address: String
    public let port: Int
    public let proto: FirewallPort.Proto

    /// What compose means by an address-less mapping
    public static let wildcard = "0.0.0.0"

    public init(address: String = PublishedHostPort.wildcard, port: Int,
                proto: FirewallPort.Proto = .tcp) {
        self.address = address
        self.port = port
        self.proto = proto
    }

    public static func isWildcard(_ address: String) -> Bool {
        address.isEmpty || address == wildcard || address == "::" || address == "[::]" || address == "*"
    }

    public func collides(with other: PublishedHostPort) -> Bool {
        guard port == other.port, proto == other.proto else { return false }
        return address == other.address
            || PublishedHostPort.isWildcard(address)
            || PublishedHostPort.isWildcard(other.address)
    }

    public var label: String { "\(port)/\(proto.rawValue)" }
}

public enum ComposePorts {
    /// Every host port published by a compose body
    public static func published(in composeContents: String) -> [PublishedHostPort] {
        var found: [PublishedHostPort] = []
        var listIndent: Int?
        for rawLine in composeContents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix { $0 == " " }.count
            if trimmed == "ports:" {
                listIndent = indent
                continue
            }
            guard let openIndent = listIndent else { continue }
            if trimmed.hasPrefix("#") { continue }
            guard trimmed.hasPrefix("- "), indent > openIndent else {
                listIndent = nil
                continue
            }
            if let entry = entry(String(trimmed.dropFirst(2))) { found.append(entry) }
        }
        return found
    }

    /// One `ports:` entry — `"IP:HOST:CONTAINER/proto"`, `"HOST:CONTAINER"`
    public static func entry(_ raw: String) -> PublishedHostPort? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where text.count >= 2 && text.hasPrefix(quote) && text.hasSuffix(quote) {
            text = String(text.dropFirst().dropLast())
        }
        var proto = FirewallPort.Proto.tcp
        if let slash = text.lastIndex(of: "/") {
            guard let named = FirewallPort.Proto(rawValue: String(text[text.index(after: slash)...]).lowercased()) else {
                return nil
            }
            proto = named
            text = String(text[text.startIndex..<slash])
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let address: String
        let hostSide: String
        switch parts.count {
        case 3: (address, hostSide) = (parts[0], parts[1])
        case 2: (address, hostSide) = (PublishedHostPort.wildcard, parts[0])
        default: return nil
        }
        guard let port = Int(hostSide), (1...65535).contains(port) else { return nil }
        return PublishedHostPort(address: address, port: port, proto: proto)
    }
}

extension ManagedService {
    /// The host ports this service takes when it is installed
    public func publishedHostPorts(_ context: ServiceContext) -> [PublishedHostPort] {
        guard let compose = composeFile(context) else {
            return firewallPorts(context).map { PublishedHostPort(port: $0.port, proto: $0.proto) }
        }
        return ComposePorts.published(in: compose.composeContents)
    }
}

import Foundation

public struct ProxyLinkConfig: Equatable, Sendable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case shadowsocks
        case vless
    }

    public let rawText: String
    public let kind: Kind
    public let host: String
    public let port: Int
    /// The `#fragment`, percent-decoded — the panel writes the device's name there
    public let label: String

    public struct VLESSParameters: Equatable, Sendable {
        /// The client id, which is the whole of the credential
        public let uuid: String
        /// `none`, `tls` or `reality`
        public let security: String
        public let sni: String
        /// The uTLS profile to imitate — `chrome`, `firefox`, and so on
        public let fingerprint: String
        public let publicKey: String
        public let shortID: String
        /// `xtls-rprx-vision`, usually
        public let flow: String
        /// The transport under the handshake: `tcp`, `ws` or `grpc`
        public let network: String
        public let path: String
        public let host: String
        /// gRPC only
        public let serviceName: String

        public init(uuid: String, security: String, sni: String, fingerprint: String,
                    publicKey: String, shortID: String, flow: String,
                    network: String, path: String, host: String, serviceName: String) {
            self.uuid = uuid
            self.security = security
            self.sni = sni
            self.fingerprint = fingerprint
            self.publicKey = publicKey
            self.shortID = shortID
            self.flow = flow
            self.network = network
            self.path = path
            self.host = host
            self.serviceName = serviceName
        }
    }

    public enum Credential: Equatable, Sendable {
        /// Shadowsocks: the cipher and the password, from the userinfo
        case shadowsocks(method: String, password: String)
        case vless(VLESSParameters)
    }

    public let credential: Credential

    /// `host:port`, the form `TunnelProfile.endpoint` is written in
    public var endpoint: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Reasons, not sentences — the same rule `WireGuardQuickConfig.ParseError` keeps
    public enum ParseError: Error, Equatable {
        case noLink(Kind)
        case noEndpoint(Kind)
        case noCredential(Kind)
        case unsupportedTransport(String)
    }

    /// What the datapath has a branch for
    static let carriedNetworks: Set<String> = ["tcp", "ws", "grpc"]
    static let carriedSecurities: Set<String> = ["none", "tls", "reality"]

    public static func kind(of text: String) -> Kind? {
        Kind.allCases.first { VPNConfigurationHandoff.link(in: text, scheme: $0.scheme) != nil }
    }

    /// - Parameters: - text: what the server answered with
    public init(parsing text: String) throws {
        guard let kind = Self.kind(of: text) else { throw ParseError.noLink(.shadowsocks) }
        try self.init(parsing: text, kind: kind)
    }

    /// - Parameters: - text: what the server answered with
    public init(parsing text: String, kind: Kind) throws {
        guard let (url, matchedText) = VPNConfigurationHandoff.link(in: text, scheme: kind.scheme) else {
            throw ParseError.noLink(kind)
        }
        let endpoint = Self.endpoint(of: url) ?? Self.legacyEndpoint(of: url)
        guard let endpoint, !endpoint.host.isEmpty,
              (1...65_535).contains(endpoint.port)
        else { throw ParseError.noEndpoint(kind) }

        self.rawText = matchedText
        self.kind = kind
        self.host = endpoint.host
        self.port = endpoint.port
        self.label = url.fragment?.removingPercentEncoding ?? url.fragment ?? ""
        switch kind {
        case .shadowsocks:
            if Self.query(of: url)["plugin"]?.isEmpty == false {
                throw ParseError.unsupportedTransport("plugin")
            }
            guard let credential = Self.shadowsocksCredential(of: url) else {
                throw ParseError.noCredential(kind)
            }
            self.credential = credential
        case .vless:
            guard let user = url.user, !user.isEmpty else {
                throw ParseError.noCredential(kind)
            }
            let query = Self.query(of: url)
            let security = query["security"] ?? "none"
            guard Self.carriedSecurities.contains(security) else {
                throw ParseError.unsupportedTransport(security)
            }
            let network = query["type"] ?? "tcp"
            guard Self.carriedNetworks.contains(network) else {
                throw ParseError.unsupportedTransport(network)
            }
            self.credential = .vless(VLESSParameters(
                uuid: user,
                security: security,
                sni: query["sni"] ?? query["peer"] ?? "",
                fingerprint: query["fp"] ?? "",
                publicKey: query["pbk"] ?? "",
                shortID: query["sid"] ?? "",
                flow: security == "none" ? "" : (query["flow"] ?? ""),
                network: network,
                path: query["path"] ?? "",
                host: query["host"] ?? "",
                serviceName: query["serviceName"] ?? ""))
        }
    }

    private static func shadowsocksCredential(of url: URL) -> Credential? {
        if let user = url.user, let password = url.password, !user.isEmpty {
            return split("\(user.removingPercentEncoding ?? user):"
                         + (password.removingPercentEncoding ?? password))
        }
        if let user = url.user, !user.isEmpty {
            let decoded = user.contains(":")
                ? (user.removingPercentEncoding ?? user)
                : (base64Decoded(user) ?? "")
            return split(decoded)
        }
        let body = url.absoluteString
            .dropFirst(url.scheme.map { $0.count + 3 } ?? 0)
            .prefix { $0 != "#" && $0 != "?" }
        guard let decoded = base64Decoded(String(body)),
              let at = decoded.lastIndex(of: "@")
        else { return nil }
        return split(String(decoded[..<at]))
    }

    /// `method:password` → the two halves
    private static func split(_ pair: String) -> Credential? {
        guard let colon = pair.firstIndex(of: ":") else { return nil }
        let method = String(pair[..<colon])
        let raw = String(pair[pair.index(after: colon)...])
        let password = method.hasPrefix("2022-") ? fullyDecoded(raw) : raw
        guard !method.isEmpty, !password.isEmpty else { return nil }
        return .shadowsocks(method: method, password: password)
    }

    /// Base64 keys never hold `%`, so stacked encodings all go
    private static func fullyDecoded(_ text: String) -> String {
        var current = text
        for _ in 0..<3 {
            guard current.contains("%"), let once = current.removingPercentEncoding, once != current else { break }
            current = once
        }
        return current
    }

    private static func query(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { result, item in
            guard let value = item.value, !value.isEmpty else { return }
            result[item.name] = value
        }
    }

    private static func endpoint(of url: URL) -> (host: String, port: Int)? {
        guard let host = url.host, !host.isEmpty, let port = url.port else { return nil }
        return (host, port)
    }

    private static func legacyEndpoint(of url: URL) -> (host: String, port: Int)? {
        let body = url.absoluteString
            .dropFirst(url.scheme.map { $0.count + 3 } ?? 0)
            .prefix { $0 != "#" && $0 != "?" }
        guard let decoded = base64Decoded(String(body)),
              let at = decoded.lastIndex(of: "@")
        else { return nil }
        let hostPort = decoded[decoded.index(after: at)...]
        guard let colon = hostPort.lastIndex(of: ":"),
              let port = Int(hostPort[hostPort.index(after: colon)...])
        else { return nil }
        return (String(hostPort[..<colon]), port)
    }

    static func base64Decoded(_ text: String) -> String? {
        var normalised = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalised.count % 4
        if remainder > 0 { normalised += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: normalised) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension ProxyLinkConfig.Kind {
    /// The URL scheme the panel writes for this protocol
    var scheme: String {
        switch self {
        case .shadowsocks: return "ss"
        case .vless: return "vless"
        }
    }
}

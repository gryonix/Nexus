import Foundation

/// One published name and where the tunnel should send it
public struct TunnelRoute: Sendable, Hashable {
    public let hostname: String
    /// What the connector dials on the server itself
    public let service: String

    public init(hostname: String, service: String = "https://127.0.0.1:443") {
        self.hostname = hostname
        self.service = service
    }
}

public struct CloudflareTunnelProvider: Sendable {
    /// Where a tunnel hostname points
    public static let tunnelDomain = "cfargotunnel.com"

    private let token: String
    private let accountID: String
    private let http: any CloudflareHTTPClient
    private let baseURL: URL

    public init(token: String,
                accountID: String,
                http: any CloudflareHTTPClient = URLSessionCloudflareHTTPClient(),
                baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!) {
        self.token = token
        self.accountID = accountID
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Discovery

    public static func accountID(token: String,
                                 http: any CloudflareHTTPClient = URLSessionCloudflareHTTPClient(),
                                 baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!)
        async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("zones"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await http.send(request)
        let payload = try CloudflarePayload(data: data, status: status)
        for zone in payload.resultArray {
            if let account = zone["account"] as? [String: Any],
               let id = account["id"] as? String, !id.isEmpty {
                return id
            }
        }
        throw CloudflareError.api(code: 0, message: "no zone in this account names its account id")
    }

    // MARK: - The tunnel

    public func findOrCreateTunnel(named name: String) async throws -> String {
        let existing = try await send(.get, path: "accounts/\(accountID)/cfd_tunnel",
                                      query: ["is_deleted": "false", "name": name])
        if let found = existing.resultArray.first(where: { ($0["name"] as? String) == name }),
           let id = found["id"] as? String, !id.isEmpty {
            return id
        }
        let created = try await send(.post, path: "accounts/\(accountID)/cfd_tunnel",
                                     body: ["name": name, "config_src": "cloudflare"])
        guard let result = created.result as? [String: Any],
              let id = result["id"] as? String, !id.isEmpty else {
            throw CloudflareError.api(code: 0, message: "the tunnel was created without an id")
        }
        return id
    }

    /// The credential the connector runs with — what goes into `TUNNEL_TOKEN`
    public func connectorToken(tunnelID: String) async throws -> String {
        let payload = try await send(.get, path: "accounts/\(accountID)/cfd_tunnel/\(tunnelID)/token")
        guard let token = payload.result as? String, !token.isEmpty else {
            throw CloudflareError.api(code: 0, message: "the tunnel returned no connector token")
        }
        return token
    }

    /// Point every published name at this server's Caddy
    public func applyIngress(tunnelID: String, routes: [TunnelRoute]) async throws {
        var ingress: [[String: Any]] = routes.map { route in
            [
                "hostname": route.hostname,
                "service": route.service,
                "originRequest": [
                    "noTLSVerify": true,
                    "originServerName": route.hostname,
                ],
            ]
        }
        ingress.append(["service": "http_status:404"])
        _ = try await send(.put, path: "accounts/\(accountID)/cfd_tunnel/\(tunnelID)/configurations",
                           body: ["config": ["ingress": ingress]])
    }

    /// Remove a tunnel
    public func deleteTunnel(id: String) async throws {
        _ = try await send(.delete, path: "accounts/\(accountID)/cfd_tunnel/\(id)")
    }

    // MARK: - The names

    @discardableResult
    public func publishHostnames(_ hostnames: [String], tunnelID: String, zone: String)
        async throws -> [String] {
        let zoneID = try await zoneID(for: zone)
        let target = "\(tunnelID).\(Self.tunnelDomain)"
        for hostname in hostnames {
            try await publish(hostname, target: target, zoneID: zoneID)
        }
        return hostnames
    }

    /// One name as a proxied CNAME, clearing its address records
    private func publish(_ hostname: String, target: String, zoneID: String) async throws {
        let existing = try await send(.get, path: "zones/\(zoneID)/dns_records", query: ["name": hostname])
        var cnameID: String?
        for record in existing.resultArray {
            guard let id = record["id"] as? String else { continue }
            switch record["type"] as? String {
            case "CNAME": cnameID = id
            case "A", "AAAA": _ = try await send(.delete, path: "zones/\(zoneID)/dns_records/\(id)")
            default: continue
            }
        }
        let body: [String: Any] = ["type": "CNAME", "name": hostname, "content": target, "ttl": 1, "proxied": true]
        if let cnameID {
            _ = try await send(.put, path: "zones/\(zoneID)/dns_records/\(cnameID)", body: body)
        } else {
            _ = try await send(.post, path: "zones/\(zoneID)/dns_records", body: body)
        }
    }

    private func zoneID(for zone: String) async throws -> String {
        let payload = try await send(.get, path: "zones", query: ["name": zone])
        guard let first = payload.resultArray.first,
              let id = first["id"] as? String, !id.isEmpty else {
            throw CloudflareError.zoneNotFound(zone)
        }
        return id
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    private func send(_ method: Method, path: String,
                      query: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> CloudflarePayload {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components?.url else { throw CloudflareError.badRequest(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        let (data, status) = try await http.send(request)
        return try CloudflarePayload(data: data, status: status)
    }
}

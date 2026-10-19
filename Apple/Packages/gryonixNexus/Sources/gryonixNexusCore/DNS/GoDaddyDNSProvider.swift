import Foundation

/// Publishes generated records through GoDaddy's v3 Domains API
public struct GoDaddyDNSProvider: DNSPublishingProvider {
    public let displayName = "GoDaddy"

    private static let defaultTTL = 3600

    private let token: String
    private let http: any GoDaddyHTTPClient
    private let baseURL: URL

    public init(token: String,
                http: any GoDaddyHTTPClient = URLSessionGoDaddyHTTPClient(),
                baseURL: URL = URL(string: "https://api.godaddy.com/v3/domains")!) {
        self.token = token
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Public surface

    /// Confirms the token works before anything is written
    public func verifyToken() async throws {
        _ = try await send(.get, path: "domain-names", query: ["limit": "1"])
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        var outcomes: [DNSPublishOutcome] = []
        for record in records {
            do {
                let relative = relativeName(record.name, zone: zone)
                let match = try await existingRecord(for: record, name: relative, zone: zone)
                if let match {
                    let record = record.merged(withExisting: match.data)
                    if match.isUpToDate(with: record) {
                        outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    } else {
                        _ = try await send(.put, path: "zones/\(zone)/dns-records/\(match.id)",
                                           body: body(for: record, zone: zone, existingTTL: match.ttl))
                        outcomes.append(DNSPublishOutcome(record: record, result: .updated))
                    }
                } else {
                    _ = try await send(.post, path: "zones/\(zone)/dns-records",
                                       body: body(for: record, zone: zone, existingTTL: nil))
                    outcomes.append(DNSPublishOutcome(record: record, result: .created))
                }
            } catch let error as GoDaddyError {
                outcomes.append(DNSPublishOutcome(record: record, result: .failed(error.message)))
            }
        }
        return outcomes
    }

    // MARK: - Naming

    private func relativeName(_ fullName: String, zone: String) -> String {
        let full = fullName.lowercased()
        let suffix = ".\(zone.lowercased())"
        if full == zone.lowercased() { return "@" }
        if full.hasSuffix(suffix) { return String(full.dropLast(suffix.count)) }
        return full
    }

    // MARK: - Existing records

    struct RemoteRecord {
        let id: String
        let data: String
        let ttl: Int?
        let priority: Int?

        func isUpToDate(with record: DNSRecord) -> Bool {
            if record.type == .srv, let srv = record.srv {
                return normalizedTarget(data) == normalizedTarget("\(srv.weight) \(srv.port) \(srv.target)")
                    && priority == srv.priority
            }
            if record.type == .mx {
                return normalizedTarget(data) == normalizedTarget(record.value)
                    && priority == record.priority
            }
            return data == record.value
        }

        private func normalizedTarget(_ value: String) -> String {
            value.hasSuffix(".") ? String(value.dropLast()) : value
        }
    }

    private func existingRecord(for record: DNSRecord, name: String,
                                zone: String) async throws -> RemoteRecord? {
        let type = record.type.rawValue
        let payload = try await send(.get, path: "zones/\(zone)/dns-records",
                                     query: ["type": type, "name": name])
        guard let item = payload.items.first(where: { item in
            (item["type"] as? String) == type
                && (item["name"] as? String)?.lowercased() == name.lowercased()
                && record.replaces(existingValue: item["data"] as? String ?? "")
        }), let id = item["recordId"] as? String else { return nil }
        return RemoteRecord(id: id, data: item["data"] as? String ?? "",
                            ttl: item["ttl"] as? Int, priority: item["priority"] as? Int)
    }

    private func body(for record: DNSRecord, zone: String, existingTTL: Int?) -> [String: Any] {
        var body: [String: Any] = [
            "type": record.type.rawValue,
            "name": relativeName(record.name, zone: zone),
            "ttl": existingTTL ?? Self.defaultTTL,
        ]
        switch record.type {
        case .mx:
            body["data"] = record.value.hasSuffix(".") ? record.value : record.value + "."
            if let priority = record.priority { body["priority"] = priority }
        case .srv:
            if let srv = record.srv {
                let target = srv.target.hasSuffix(".") ? srv.target : srv.target + "."
                body["data"] = "\(srv.weight) \(srv.port) \(target)"
                body["priority"] = srv.priority
            }
        case .a, .aaaa, .txt:
            body["data"] = record.value
        }
        return body
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST", put = "PUT" }

    private func send(_ method: Method, path: String,
                      query: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> GoDaddyPayload {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components?.url else { throw GoDaddyError.badRequest(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body,
                                                          options: [.sortedKeys])
        }

        let (data, status) = try await http.send(request)
        return try GoDaddyPayload(data: data, status: status, zone: zoneName(from: path))
    }

    private func zoneName(from path: String) -> String {
        guard path.hasPrefix("zones/") else { return "" }
        let rest = path.dropFirst("zones/".count)
        return String(rest.prefix { $0 != "/" })
    }
}

// MARK: - Transport seam

public protocol GoDaddyHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionGoDaddyHTTPClient: GoDaddyHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

// MARK: - Responses

struct GoDaddyPayload {
    let items: [[String: Any]]

    init(data: Data, status: Int, zone: String) throws {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200...299).contains(status) else {
            let message = object?["message"] as? String ?? "HTTP \(status)"
            if status == 401 || status == 403 {
                throw GoDaddyError.invalidToken
            }
            if status == 404 {
                throw GoDaddyError.zoneNotFound(zone)
            }
            throw GoDaddyError.api(status: status, message: message)
        }
        items = (object?["items"] as? [[String: Any]]) ?? []
    }
}

public enum GoDaddyError: Error, LocalizedError, Hashable {
    case invalidToken
    case zoneNotFound(String)
    case api(status: Int, message: String)
    case badRequest(String)

    public var message: String {
        switch self {
        case .invalidToken:
            return "Invalid API token"
        case .zoneNotFound(let zone):
            return "no domain named \(zone) in this account"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

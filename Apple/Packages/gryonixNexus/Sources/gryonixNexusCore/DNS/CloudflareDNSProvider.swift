import Foundation

public struct CloudflareDNSProvider: DNSPublishingProvider {
    public let displayName = "Cloudflare"

    private let token: String
    private let http: any CloudflareHTTPClient
    private let baseURL: URL

    public init(token: String,
                http: any CloudflareHTTPClient = URLSessionCloudflareHTTPClient(),
                baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!) {
        self.token = token
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Public surface

    /// Confirms the token works before anything is written
    public func verifyToken() async throws {
        _ = try await send(.get, path: "user/tokens/verify")
    }

    /// The zone id Cloudflare knows this domain by
    public func zoneID(for zone: String) async throws -> String {
        let payload = try await send(.get, path: "zones", query: ["name": zone])
        guard let first = payload.resultArray.first,
              let id = first["id"] as? String, !id.isEmpty else {
            throw CloudflareError.zoneNotFound(zone)
        }
        return id
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await applyReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func applyReportingOutcomes(_ records: [DNSRecord],
                                       zone: String) async throws -> [Outcome] {
        let zoneID = try await zoneID(for: zone)
        let existing = try await existingRecords(zoneID: zoneID)
        let records = DNSRecord.merging(records) { record in
            existing.first { $0.matches(record) }.map { RemoteRecord.unquoted($0.content) }
        }
        var outcomes: [Outcome] = []

        for record in records {
            do {
                let match = existing.first { $0.matches(record) }
                if let match {
                    if match.isUpToDate(with: record) {
                        outcomes.append(Outcome(record: record, result: .unchanged))
                    } else {
                        _ = try await send(.put, path: "zones/\(zoneID)/dns_records/\(match.id)",
                                           body: body(for: record))
                        outcomes.append(Outcome(record: record, result: .updated))
                    }
                } else {
                    _ = try await send(.post, path: "zones/\(zoneID)/dns_records",
                                       body: body(for: record))
                    outcomes.append(Outcome(record: record, result: .created))
                }
            } catch let error as CloudflareError {
                outcomes.append(Outcome(record: record, result: .failed(error.message)))
            }
        }
        return outcomes
    }

    /// What became of one record
    public typealias Outcome = DNSPublishOutcome

    public func removeAddressRecords(named names: [String], pointingAt address: String,
                                     zone: String) async throws -> [String] {
        let zoneID = try await zoneID(for: zone)
        let wanted = Set(names.map { $0.lowercased() })
        var removed: [String] = []
        for record in try await existingRecords(zoneID: zoneID)
        where record.type == "A" && record.content == address && wanted.contains(record.name.lowercased()) {
            _ = try await send(.delete, path: "zones/\(zoneID)/dns_records/\(record.id)")
            removed.append(record.name)
        }
        return removed
    }

    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        try await applyReportingOutcomes(records, zone: zone)
    }

    // MARK: - Existing records

    struct RemoteRecord {
        let id: String
        let type: String
        let name: String
        let content: String
        let priority: Int?

        func matches(_ record: DNSRecord) -> Bool {
            type == record.type.rawValue
                && name.lowercased() == record.name.lowercased()
                && record.replaces(existingValue: Self.unquoted(content))
        }

        func isUpToDate(with record: DNSRecord) -> Bool {
            if record.type == .srv, let srv = record.srv {
                return content.hasSuffix("\(srv.weight) \(srv.port) \(srv.target)")
                    && priority == srv.priority
            }
            if record.type == .txt {
                return content.hasPrefix("\"") && Self.unquoted(content) == record.value
            }
            return content == record.value && priority == record.priority
        }

        /// `"a" "b"` read back as `ab`
        static func unquoted(_ content: String) -> String {
            guard content.hasPrefix("\"") else { return content }
            var text = "", inside = false, escaped = false
            for character in content {
                if escaped { text.append(character); escaped = false }
                else if character == "\\" && inside { escaped = true }
                else if character == "\"" { inside.toggle() }
                else if inside { text.append(character) }
            }
            return text
        }
    }

    /// Every record in the zone, following Cloudflare's pagination
    private func existingRecords(zoneID: String) async throws -> [RemoteRecord] {
        var page = 1
        var all: [RemoteRecord] = []
        while true {
            let payload = try await send(.get, path: "zones/\(zoneID)/dns_records",
                                         query: ["per_page": "100", "page": String(page)])
            let batch = payload.resultArray.compactMap { item -> RemoteRecord? in
                guard let id = item["id"] as? String,
                      let type = item["type"] as? String,
                      let name = item["name"] as? String,
                      let content = item["content"] as? String else { return nil }
                return RemoteRecord(id: id, type: type, name: name, content: content,
                                    priority: item["priority"] as? Int)
            }
            all.append(contentsOf: batch)
            guard batch.count == 100, page < 50 else { return all }
            page += 1
        }
    }

    private func body(for record: DNSRecord) -> [String: Any] {
        var body: [String: Any] = [
            "type": record.type.rawValue,
            "name": record.name,
            "content": record.type == .txt ? bindTXTRData(record.value, chunkSize: .max) : record.value,
            "ttl": 1,
            "proxied": false
        ]
        if let priority = record.priority { body["priority"] = priority }
        if record.type == .srv, let srv = record.srv {
            body["data"] = [
                "priority": srv.priority,
                "weight": srv.weight,
                "port": srv.port,
                "target": srv.target
            ]
        }
        if let comment = record.comment { body["comment"] = comment }
        return body
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
                .sorted { $0.name < $1.name }   // deterministic, so a test can pin the URL
        }
        guard let url = components?.url else { throw CloudflareError.badRequest(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body,
                                                          options: [.sortedKeys])
        }

        let (data, status) = try await http.send(request)
        return try CloudflarePayload(data: data, status: status)
    }
}

// MARK: - Transport seam

/// The one call this provider makes on the network
public protocol CloudflareHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionCloudflareHTTPClient: CloudflareHTTPClient {
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

struct CloudflarePayload {
    let result: Any?

    var resultArray: [[String: Any]] { result as? [[String: Any]] ?? [] }

    init(data: Data, status: Int) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudflareError.unreadableResponse(status: status)
        }
        let success = object["success"] as? Bool ?? false
        guard success else {
            throw CloudflareError(status: status, errors: object["errors"] as? [[String: Any]] ?? [])
        }
        result = object["result"]
    }
}

/// What went wrong, in the terms Cloudflare used
public enum CloudflareError: Error, LocalizedError, Hashable {
    case invalidToken
    case zoneNotFound(String)
    case api(code: Int, message: String)
    case unreadableResponse(status: Int)
    case badRequest(String)

    init(status: Int, errors: [[String: Any]]) {
        let code = errors.first?["code"] as? Int ?? 0
        let message = errors.first?["message"] as? String ?? "HTTP \(status)"
        if code == 1000 || code == 6003 || status == 401 || status == 403 {
            self = .invalidToken
        } else {
            self = .api(code: code, message: message)
        }
    }

    /// The sentence to show
    public var message: String {
        switch self {
        case .invalidToken:
            return "Invalid API token"
        case .zoneNotFound(let zone):
            return "no zone named \(zone) in this account"
        case .api(let code, let message):
            return "\(message) (Cloudflare code \(code))"
        case .unreadableResponse(let status):
            return "unreadable response from Cloudflare (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

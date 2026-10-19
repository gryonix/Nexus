import Foundation

public struct DigitalOceanDNSProvider: DNSPublishingProvider {
    public let displayName = "DigitalOcean"

    private let token: String
    private let http: any DigitalOceanHTTPClient
    private let baseURL: URL

    public init(token: String,
                http: any DigitalOceanHTTPClient = URLSessionDigitalOceanHTTPClient(),
                baseURL: URL = URL(string: "https://api.digitalocean.com/v2")!) {
        self.token = token
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Public surface

    /// Confirms the token works before anything is written
    public func verifyToken() async throws {
        _ = try await send(.get, path: "account")
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        let existing = try await existingRecords(zone: zone)
        let records = DNSRecord.merging(records) { record in
            let relative = relativeName(record.name, zone: zone)
            return existing.first {
                $0.matches(type: record.type.rawValue, name: relative) && record.replaces(existingValue: $0.data)
            }?.data
        }
        var outcomes: [DNSPublishOutcome] = []

        for record in records {
            do {
                let relative = relativeName(record.name, zone: zone)
                let match = existing.first { $0.matches(type: record.type.rawValue, name: relative) && record.replaces(existingValue: $0.data) }
                if let match {
                    if match.isUpToDate(with: record) {
                        outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    } else {
                        _ = try await send(.put, path: "domains/\(zone)/records/\(match.id)",
                                           body: body(for: record, zone: zone))
                        outcomes.append(DNSPublishOutcome(record: record, result: .updated))
                    }
                } else {
                    _ = try await send(.post, path: "domains/\(zone)/records",
                                       body: body(for: record, zone: zone))
                    outcomes.append(DNSPublishOutcome(record: record, result: .created))
                }
            } catch let error as DigitalOceanError {
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
        let id: Int
        let type: String
        let name: String
        let data: String
        let priority: Int?

        func matches(type matchType: String, name matchName: String) -> Bool {
            type == matchType && name.lowercased() == matchName.lowercased()
        }

        func isUpToDate(with record: DNSRecord) -> Bool {
            if record.type == .srv, let srv = record.srv {
                return normalizedTarget(data) == normalizedTarget(srv.target)
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

    private func existingRecords(zone: String) async throws -> [RemoteRecord] {
        var page = 1
        var all: [RemoteRecord] = []
        while true {
            let payload = try await send(.get, path: "domains/\(zone)/records",
                                         query: ["per_page": "200", "page": String(page)])
            let batch = payload.records.compactMap { item -> RemoteRecord? in
                guard let id = item["id"] as? Int,
                      let type = item["type"] as? String,
                      let name = item["name"] as? String else { return nil }
                let data = item["data"] as? String ?? ""
                return RemoteRecord(id: id, type: type, name: name, data: data,
                                    priority: item["priority"] as? Int)
            }
            all.append(contentsOf: batch)
            guard batch.count == 200, page < 50 else { return all }
            page += 1
        }
    }

    private func body(for record: DNSRecord, zone: String) -> [String: Any] {
        var body: [String: Any] = [
            "type": record.type.rawValue,
            "name": relativeName(record.name, zone: zone)
        ]
        switch record.type {
        case .mx:
            body["data"] = record.value.hasSuffix(".") ? record.value : record.value + "."
            if let priority = record.priority { body["priority"] = priority }
        case .srv:
            if let srv = record.srv {
                body["data"] = srv.target.hasSuffix(".") ? srv.target : srv.target + "."
                body["priority"] = srv.priority
                body["weight"] = srv.weight
                body["port"] = srv.port
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
                      body: [String: Any]? = nil) async throws -> DigitalOceanPayload {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components?.url else { throw DigitalOceanError.badRequest(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body,
                                                          options: [.sortedKeys])
        }

        let (data, status) = try await http.send(request)
        return try DigitalOceanPayload(data: data, status: status, zone: zoneName(from: path))
    }

    private func zoneName(from path: String) -> String {
        guard path.hasPrefix("domains/") else { return "" }
        let rest = path.dropFirst("domains/".count)
        return String(rest.prefix { $0 != "/" })
    }
}

// MARK: - Transport seam

public protocol DigitalOceanHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionDigitalOceanHTTPClient: DigitalOceanHTTPClient {
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

struct DigitalOceanPayload {
    let records: [[String: Any]]

    init(data: Data, status: Int, zone: String) throws {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200...299).contains(status) else {
            let message = object?["message"] as? String ?? "HTTP \(status)"
            if status == 401 || status == 403 {
                throw DigitalOceanError.invalidToken
            }
            if status == 404 {
                throw DigitalOceanError.zoneNotFound(zone)
            }
            throw DigitalOceanError.api(status: status, message: message)
        }
        guard let object else {
            throw DigitalOceanError.unreadableResponse(status: status)
        }
        records = (object["domain_records"] as? [[String: Any]])
            ?? (object["domain_record"] as? [String: Any]).map { [$0] }
            ?? []
    }
}

public enum DigitalOceanError: Error, LocalizedError, Hashable {
    case invalidToken
    case zoneNotFound(String)
    case api(status: Int, message: String)
    case unreadableResponse(status: Int)
    case badRequest(String)

    public var message: String {
        switch self {
        case .invalidToken:
            return "Invalid API token"
        case .zoneNotFound(let zone):
            return "no domain named \(zone) in this account"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .unreadableResponse(let status):
            return "unreadable response from DigitalOcean (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

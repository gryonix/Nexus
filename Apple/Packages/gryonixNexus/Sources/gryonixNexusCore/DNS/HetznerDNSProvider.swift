import Foundation

public struct HetznerDNSProvider: DNSPublishingProvider {
    public let displayName = "Hetzner"

    private let token: String
    private let http: any HetznerHTTPClient
    private let baseURL: URL

    public init(token: String,
                http: any HetznerHTTPClient = URLSessionHetznerHTTPClient(),
                baseURL: URL = URL(string: "https://dns.hetzner.com/api/v1")!) {
        self.token = token
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Public surface

    /// Confirms the token works before anything is written
    public func verifyToken() async throws {
        _ = try await send(.get, path: "zones", query: ["per_page": "1"])
    }

    public func zoneID(for zone: String) async throws -> String {
        let payload = try await send(.get, path: "zones", query: ["name": zone])
        guard let first = payload.array(for: "zones").first,
              let id = first["id"] as? String, !id.isEmpty else {
            throw HetznerError.zoneNotFound(zone)
        }
        return id
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        let zoneID = try await zoneID(for: zone)
        let existing = try await existingRecords(zoneID: zoneID)
        let records = DNSRecord.merging(records) { record in
            let relative = relativeName(record.name, zone: zone)
            return existing.first {
                $0.matches(type: record.type.rawValue, name: relative) && record.replaces(existingValue: $0.value)
            }?.value
        }
        var outcomes: [DNSPublishOutcome] = []

        for record in records {
            do {
                let relative = relativeName(record.name, zone: zone)
                let value = value(for: record)
                let match = existing.first { $0.matches(type: record.type.rawValue, name: relative) && record.replaces(existingValue: $0.value) }
                if let match {
                    if match.isUpToDate(value: value) {
                        outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    } else {
                        _ = try await send(.put, path: "records/\(match.id)",
                                           body: body(zoneID: zoneID, name: relative,
                                                     record: record, value: value))
                        outcomes.append(DNSPublishOutcome(record: record, result: .updated))
                    }
                } else {
                    _ = try await send(.post, path: "records",
                                       body: body(zoneID: zoneID, name: relative,
                                                 record: record, value: value))
                    outcomes.append(DNSPublishOutcome(record: record, result: .created))
                }
            } catch let error as HetznerError {
                outcomes.append(DNSPublishOutcome(record: record, result: .failed(error.message)))
            }
        }
        return outcomes
    }

    // MARK: - Naming and values

    private func relativeName(_ fullName: String, zone: String) -> String {
        let full = fullName.lowercased()
        let suffix = ".\(zone.lowercased())"
        if full == zone.lowercased() { return "@" }
        if full.hasSuffix(suffix) { return String(full.dropLast(suffix.count)) }
        return full
    }

    /// The whole rdata as one line — see the type comment
    private func value(for record: DNSRecord) -> String {
        switch record.type {
        case .mx:
            let target = record.value.hasSuffix(".") ? record.value : record.value + "."
            return "\(record.priority ?? 0) \(target)"
        case .srv:
            guard let srv = record.srv else { return record.value }
            let target = srv.target.hasSuffix(".") ? srv.target : srv.target + "."
            return "\(srv.priority) \(srv.weight) \(srv.port) \(target)"
        case .a, .aaaa, .txt:
            return record.value
        }
    }

    // MARK: - Existing records

    struct RemoteRecord {
        let id: String
        let type: String
        let name: String
        let value: String

        func matches(type matchType: String, name matchName: String) -> Bool {
            type == matchType && name.lowercased() == matchName.lowercased()
        }

        func isUpToDate(value target: String) -> Bool {
            normalized(value) == normalized(target)
        }

        private func normalized(_ text: String) -> String {
            text.hasSuffix(".") ? String(text.dropLast()) : text
        }
    }

    private func existingRecords(zoneID: String) async throws -> [RemoteRecord] {
        var page = 1
        var all: [RemoteRecord] = []
        while true {
            let payload = try await send(.get, path: "records",
                                         query: ["zone_id": zoneID, "per_page": "100",
                                                 "page": String(page)])
            let batch = payload.array(for: "records").compactMap { item -> RemoteRecord? in
                guard let id = item["id"] as? String,
                      let type = item["type"] as? String,
                      let name = item["name"] as? String,
                      let value = item["value"] as? String else { return nil }
                return RemoteRecord(id: id, type: type, name: name, value: value)
            }
            all.append(contentsOf: batch)
            let lastPage = (payload.object(for: "meta")?["pagination"] as? [String: Any])?["last_page"] as? Int
            guard let lastPage, page < lastPage, page < 50 else { return all }
            page += 1
        }
    }

    private func body(zoneID: String, name: String, record: DNSRecord, value: String) -> [String: Any] {
        [
            "zone_id": zoneID,
            "type": record.type.rawValue,
            "name": name,
            "value": value,
            "ttl": 300
        ]
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST", put = "PUT" }

    private func send(_ method: Method, path: String,
                      query: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> HetznerPayload {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components?.url else { throw HetznerError.badRequest(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(token, forHTTPHeaderField: "Auth-API-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body,
                                                          options: [.sortedKeys])
        }

        let (data, status) = try await http.send(request)
        return try HetznerPayload(data: data, status: status)
    }
}

// MARK: - Transport seam

public protocol HetznerHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionHetznerHTTPClient: HetznerHTTPClient {
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

struct HetznerPayload {
    private let object: [String: Any]

    func array(for key: String) -> [[String: Any]] { object[key] as? [[String: Any]] ?? [] }
    func object(for key: String) -> [String: Any]? { object[key] as? [String: Any] }

    init(data: Data, status: Int) throws {
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200...299).contains(status) else {
            let message = (parsed?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            if status == 401 || status == 403 {
                throw HetznerError.invalidToken
            }
            throw HetznerError.api(status: status, message: message)
        }
        guard let parsed else { throw HetznerError.unreadableResponse(status: status) }
        object = parsed
    }
}

public enum HetznerError: Error, LocalizedError, Hashable {
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
            return "no zone named \(zone) in this account"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .unreadableResponse(let status):
            return "unreadable response from Hetzner (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

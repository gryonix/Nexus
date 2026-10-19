import Foundation

public struct PorkbunDNSProvider: DNSPublishingProvider {
    public let displayName = "Porkbun"

    private let apiKey: String
    private let secretAPIKey: String
    private let http: any PorkbunHTTPClient
    private let baseURL: URL

    public init(token: String,
                http: any PorkbunHTTPClient = URLSessionPorkbunHTTPClient(),
                baseURL: URL = URL(string: "https://api.porkbun.com/api/json/v3")!) {
        if let colon = token.firstIndex(of: ":") {
            self.apiKey = String(token[token.startIndex..<colon])
            self.secretAPIKey = String(token[token.index(after: colon)...])
        } else {
            self.apiKey = token
            self.secretAPIKey = ""
        }
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Public surface

    /// Confirms the credentials work before anything is written
    public func verifyToken() async throws {
        guard !secretAPIKey.isEmpty else { throw PorkbunError.malformedToken }
        _ = try await send(.post, path: "ping", isPing: true)
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        guard !secretAPIKey.isEmpty else { throw PorkbunError.malformedToken }
        let existing = try await existingRecords(zone: zone)
        let records = DNSRecord.merging(records) { record in
            existing.first {
                $0.matches(type: record.type.rawValue, name: record.name) && record.replaces(existingValue: $0.content)
            }?.content
        }
        var outcomes: [DNSPublishOutcome] = []

        for record in records {
            do {
                let relative = relativeName(record.name, zone: zone)
                let content = content(for: record)
                let match = existing.first { $0.matches(type: record.type.rawValue, name: record.name) && record.replaces(existingValue: $0.content) }
                if let match {
                    if match.isUpToDate(content: content, priority: record.priority ?? record.srv?.priority) {
                        outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    } else {
                        _ = try await send(.post, path: "dns/edit/\(zone)/\(match.id)",
                                           body: editBody(record: record, relative: relative, content: content))
                        outcomes.append(DNSPublishOutcome(record: record, result: .updated))
                    }
                } else {
                    _ = try await send(.post, path: "dns/create/\(zone)",
                                       body: createBody(record: record, relative: relative, content: content))
                    outcomes.append(DNSPublishOutcome(record: record, result: .created))
                }
            } catch let error as PorkbunError {
                outcomes.append(DNSPublishOutcome(record: record, result: .failed(error.message)))
            }
        }
        return outcomes
    }

    // MARK: - Naming and values

    private func relativeName(_ fullName: String, zone: String) -> String {
        let full = fullName.lowercased()
        let suffix = ".\(zone.lowercased())"
        if full == zone.lowercased() { return "" }
        if full.hasSuffix(suffix) { return String(full.dropLast(suffix.count)) }
        return full
    }

    private func content(for record: DNSRecord) -> String {
        switch record.type {
        case .mx:
            return record.value.hasSuffix(".") ? record.value : record.value + "."
        case .srv:
            guard let srv = record.srv else { return record.value }
            return srv.target.hasSuffix(".") ? srv.target : srv.target + "."
        case .a, .aaaa, .txt:
            return record.value
        }
    }

    private func createBody(record: DNSRecord, relative: String, content: String) -> [String: Any] {
        var body: [String: Any] = [
            "apikey": apiKey,
            "secretapikey": secretAPIKey,
            "name": relative,
            "type": record.type.rawValue,
            "content": content
        ]
        if let priority = record.priority ?? record.srv?.priority {
            body["prio"] = priority
        }
        return body
    }

    private func editBody(record: DNSRecord, relative: String, content: String) -> [String: Any] {
        var body: [String: Any] = [
            "apikey": apiKey,
            "secretapikey": secretAPIKey,
            "name": relative,
            "type": record.type.rawValue,
            "content": content
        ]
        if let priority = record.priority ?? record.srv?.priority {
            body["prio"] = priority
        }
        return body
    }

    // MARK: - Existing records

    struct RemoteRecord {
        let id: String
        let type: String
        let name: String
        let content: String
        let priority: Int?

        func matches(type matchType: String, name matchName: String) -> Bool {
            type == matchType && name.lowercased() == matchName.lowercased()
        }

        func isUpToDate(content target: String, priority targetPriority: Int?) -> Bool {
            normalized(content) == normalized(target) && priority == targetPriority
        }

        private func normalized(_ text: String) -> String {
            text.hasSuffix(".") ? String(text.dropLast()) : text
        }
    }

    /// Every record in the zone
    private func existingRecords(zone: String) async throws -> [RemoteRecord] {
        let payload = try await send(.post, path: "dns/retrieve/\(zone)",
                                     body: ["apikey": apiKey, "secretapikey": secretAPIKey])
        return payload.array(for: "records").compactMap { item -> RemoteRecord? in
            guard let id = item["id"] as? String,
                  let type = item["type"] as? String,
                  let name = item["name"] as? String,
                  let content = item["content"] as? String else { return nil }
            return RemoteRecord(id: id, type: type, name: name, content: content,
                                priority: Self.intValue(item["prio"]))
        }
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let number = raw as? Int { return number }
        if let text = raw as? String { return Int(text) }
        return nil
    }

    // MARK: - Transport

    private enum Method: String { case post = "POST" }

    private func send(_ method: Method, path: String,
                      body: [String: Any] = [:], isPing: Bool = false) async throws -> PorkbunPayload {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        if isPing {
            payload["apikey"] = apiKey
            payload["secretapikey"] = secretAPIKey
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (data, status) = try await http.send(request)
        if isPing, !(200...299).contains(status) { throw PorkbunError.invalidToken }
        return try PorkbunPayload(data: data, status: status, zone: zoneName(from: path))
    }

    private func zoneName(from path: String) -> String {
        for prefix in ["dns/retrieve/", "dns/create/", "dns/edit/"] {
            if path.hasPrefix(prefix) {
                let rest = path.dropFirst(prefix.count)
                return String(rest.prefix { $0 != "/" })
            }
        }
        return ""
    }
}

// MARK: - Transport seam

public protocol PorkbunHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionPorkbunHTTPClient: PorkbunHTTPClient {
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

struct PorkbunPayload {
    private let object: [String: Any]

    func array(for key: String) -> [[String: Any]] { object[key] as? [[String: Any]] ?? [] }

    init(data: Data, status: Int, zone: String) throws {
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200...299).contains(status) else {
            let message = parsed?["message"] as? String ?? "HTTP \(status)"
            if status == 404 { throw PorkbunError.zoneNotFound(zone) }
            throw PorkbunError.api(status: status, message: message)
        }
        guard let parsed else { throw PorkbunError.unreadableResponse(status: status) }
        if (parsed["status"] as? String) == "ERROR" {
            let message = parsed["message"] as? String ?? "unknown error"
            throw PorkbunError.api(status: status, message: message)
        }
        object = parsed
    }
}

public enum PorkbunError: Error, LocalizedError, Hashable {
    case malformedToken
    case invalidToken
    case zoneNotFound(String)
    case api(status: Int, message: String)
    case unreadableResponse(status: Int)

    public var message: String {
        switch self {
        case .malformedToken:
            return "Paste both keys as apikey:secretapikey"
        case .invalidToken:
            return "Invalid API key or secret key"
        case .zoneNotFound(let zone):
            return "no domain named \(zone) in this account"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .unreadableResponse(let status):
            return "unreadable response from Porkbun (HTTP \(status))"
        }
    }

    public var errorDescription: String? { message }
}

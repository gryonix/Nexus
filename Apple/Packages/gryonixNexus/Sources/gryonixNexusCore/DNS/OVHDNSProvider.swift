import CryptoKit
import Foundation

public struct OVHDNSProvider: DNSPublishingProvider {
    public let displayName = "OVHcloud"

    private let applicationKey: String
    private let applicationSecret: String
    private let consumerKey: String
    private let http: any OVHHTTPClient
    private let baseURL: URL
    private let clock: @Sendable () -> Date

    public init(token: String,
                http: any OVHHTTPClient = URLSessionOVHHTTPClient(),
                baseURL: URL = URL(string: "https://eu.api.ovh.com/1.0")!,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        let parts = token.split(separator: ":", maxSplits: 2,
                                omittingEmptySubsequences: false).map(String.init)
        self.applicationKey = parts.count > 0 ? parts[0] : ""
        self.applicationSecret = parts.count > 1 ? parts[1] : ""
        self.consumerKey = parts.count > 2 ? parts[2] : ""
        self.http = http
        self.baseURL = baseURL
        self.clock = clock
    }

    private var hasAllKeys: Bool {
        !applicationKey.isEmpty && !applicationSecret.isEmpty && !consumerKey.isEmpty
    }

    // MARK: - Public surface

    /// Confirms the credentials work before anything is written
    public func verifyToken() async throws {
        guard hasAllKeys else { throw OVHError.malformedToken }
        let delta = try await serverTimeDelta()
        _ = try await send(.get, path: "/domain/zone", delta: delta)
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        guard hasAllKeys else { throw OVHError.malformedToken }
        let delta = try await serverTimeDelta()
        var outcomes: [DNSPublishOutcome] = []
        var changed = false

        for record in records {
            do {
                let sub = relativeName(record.name, zone: zone)
                let target = target(for: record)
                let existing = try await matchingRecords(zone: zone, type: record.type.rawValue,
                                                         subDomain: sub, delta: delta)
                if let match = existing.first(where: { record.replaces(existingValue: $0.target) }) {
                    let record = record.merged(withExisting: match.target)
                    let target = self.target(for: record)
                    if normalized(match.target) == normalized(target) {
                        outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    } else {
                        _ = try await send(.put, path: "/domain/zone/\(zone)/record/\(match.id)",
                                           body: ["subDomain": sub, "target": target, "ttl": 3600],
                                           delta: delta)
                        changed = true
                        outcomes.append(DNSPublishOutcome(record: record, result: .updated))
                    }
                } else {
                    _ = try await send(.post, path: "/domain/zone/\(zone)/record",
                                       body: ["fieldType": record.type.rawValue,
                                              "subDomain": sub, "target": target, "ttl": 3600],
                                       delta: delta)
                    changed = true
                    outcomes.append(DNSPublishOutcome(record: record, result: .created))
                }
            } catch let error as OVHError {
                outcomes.append(DNSPublishOutcome(record: record, result: .failed(error.message)))
            }
        }

        if changed {
            _ = try await send(.post, path: "/domain/zone/\(zone)/refresh", delta: delta)
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

    private func target(for record: DNSRecord) -> String {
        switch record.type {
        case .mx:
            let host = record.value.hasSuffix(".") ? record.value : record.value + "."
            return "\(record.priority ?? 0) \(host)"
        case .srv:
            guard let srv = record.srv else { return record.value }
            let host = srv.target.hasSuffix(".") ? srv.target : srv.target + "."
            return "\(srv.priority) \(srv.weight) \(srv.port) \(host)"
        case .a, .aaaa, .txt:
            return record.value
        }
    }

    private func normalized(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    // MARK: - Existing records

    struct RemoteRecord {
        let id: Int
        let target: String
    }

    private func matchingRecords(zone: String, type: String, subDomain: String,
                                 delta: Int) async throws -> [RemoteRecord] {
        let ids = try await send(.get, path: "/domain/zone/\(zone)/record",
                                 query: ["fieldType": type, "subDomain": subDomain],
                                 delta: delta).ints()
        var records: [RemoteRecord] = []
        for id in ids {
            let object = try await send(.get, path: "/domain/zone/\(zone)/record/\(id)",
                                        delta: delta).object()
            let target = object?["target"] as? String ?? ""
            records.append(RemoteRecord(id: id, target: target))
        }
        return records
    }

    // MARK: - Signing

    private func serverTimeDelta() async throws -> Int {
        let url = baseURL.appendingPathComponent("/auth/time")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, status) = try await http.send(request)
        guard (200...299).contains(status),
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              let serverNow = Int(text) else {
            throw OVHError.unreadableResponse(status: status)
        }
        return serverNow - Int(clock().timeIntervalSince1970)
    }

    private func signature(method: String, url: String, body: String, timestamp: String) -> String {
        let base = [applicationSecret, consumerKey, method, url, body, timestamp].joined(separator: "+")
        let digest = Insecure.SHA1.hash(data: Data(base.utf8))
        return "$1$" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST", put = "PUT" }

    private func send(_ method: Method, path: String,
                      query: [String: String] = [:],
                      body: [String: Any]? = nil,
                      delta: Int) async throws -> OVHResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components?.url else { throw OVHError.badRequest(path) }

        let bodyData = try body.map {
            try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
        }
        let bodyText = bodyData.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let target = url.absoluteString
        let timestamp = String(Int(clock().timeIntervalSince1970) + delta)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(applicationKey, forHTTPHeaderField: "X-Ovh-Application")
        request.setValue(consumerKey, forHTTPHeaderField: "X-Ovh-Consumer")
        request.setValue(timestamp, forHTTPHeaderField: "X-Ovh-Timestamp")
        request.setValue(signature(method: method.rawValue, url: target,
                                   body: bodyText, timestamp: timestamp),
                         forHTTPHeaderField: "X-Ovh-Signature")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, status) = try await http.send(request)
        return try OVHResponse(data: data, status: status, zone: zoneName(from: path))
    }

    private func zoneName(from path: String) -> String {
        let prefix = "/domain/zone/"
        guard path.hasPrefix(prefix) else { return "" }
        return String(path.dropFirst(prefix.count).prefix { $0 != "/" })
    }
}

// MARK: - Transport seam

public protocol OVHHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionOVHHTTPClient: OVHHTTPClient {
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

struct OVHResponse {
    private let json: Any

    func ints() -> [Int] { (json as? [Any])?.compactMap { $0 as? Int } ?? [] }
    func strings() -> [String] { (json as? [Any])?.compactMap { $0 as? String } ?? [] }
    func object() -> [String: Any]? { json as? [String: Any] }

    init(data: Data, status: Int, zone: String) throws {
        let parsed = try? JSONSerialization.jsonObject(with: data,
                                                      options: [.allowFragments])
        guard (200...299).contains(status) else {
            let message = (parsed as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            if status == 401 || status == 403 { throw OVHError.invalidToken }
            if status == 404, !zone.isEmpty { throw OVHError.zoneNotFound(zone) }
            throw OVHError.api(status: status, message: message)
        }
        guard let parsed else { throw OVHError.unreadableResponse(status: status) }
        json = parsed
    }
}

public enum OVHError: Error, LocalizedError, Hashable {
    case malformedToken
    case invalidToken
    case zoneNotFound(String)
    case api(status: Int, message: String)
    case unreadableResponse(status: Int)
    case badRequest(String)

    public var message: String {
        switch self {
        case .malformedToken:
            return "Paste all three keys as applicationKey:applicationSecret:consumerKey"
        case .invalidToken:
            return "Invalid application key, secret or consumer key"
        case .zoneNotFound(let zone):
            return "no DNS zone named \(zone) in this account"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .unreadableResponse(let status):
            return "unreadable response from OVH (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

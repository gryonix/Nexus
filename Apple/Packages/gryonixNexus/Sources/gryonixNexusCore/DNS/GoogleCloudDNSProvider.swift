import Foundation
import Security

public struct GoogleCloudDNSProvider: DNSPublishingProvider {
    public let displayName = "Google Cloud DNS"

    private let projectID: String
    private let clientEmail: String
    private let privateKeyPEM: String
    private let tokenURI: String
    private let http: any GoogleCloudDNSHTTPClient
    private let baseURL: URL
    private let tokenURL: URL
    private let clock: @Sendable () -> Date

    /// Read-write scope: publishing records is a write
    private static let scope = "https://www.googleapis.com/auth/ndev.clouddns.readwrite"

    public init(token: String,
                http: any GoogleCloudDNSHTTPClient = URLSessionGoogleCloudDNSHTTPClient(),
                baseURL: URL = URL(string: "https://dns.googleapis.com/dns/v1")!,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        if let data = token.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let clientEmail = object["client_email"] as? String,
           let privateKey = object["private_key"] as? String,
           let projectID = object["project_id"] as? String,
           !clientEmail.isEmpty, !privateKey.isEmpty, !projectID.isEmpty {
            self.clientEmail = clientEmail
            self.privateKeyPEM = privateKey
            self.projectID = projectID
            self.tokenURI = object["token_uri"] as? String ?? "https://oauth2.googleapis.com/token"
        } else {
            self.clientEmail = ""
            self.privateKeyPEM = ""
            self.projectID = ""
            self.tokenURI = "https://oauth2.googleapis.com/token"
        }
        self.http = http
        self.baseURL = baseURL
        self.tokenURL = URL(string: self.tokenURI) ?? URL(string: "https://oauth2.googleapis.com/token")!
        self.clock = clock
    }

    private var hasCredentials: Bool {
        !clientEmail.isEmpty && !privateKeyPEM.isEmpty && !projectID.isEmpty
    }

    // MARK: - Public surface

    public func verifyToken() async throws {
        guard hasCredentials else { throw GoogleCloudDNSError.malformedToken }
        let token = try await accessToken()
        _ = try await send(.get, path: "projects/\(projectID)/managedZones",
                           query: ["maxResults": "1"], token: token)
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        guard hasCredentials else { throw GoogleCloudDNSError.malformedToken }
        let token = try await accessToken()
        let managedZone = try await managedZoneName(for: zone, token: token)
        var outcomes: [DNSPublishOutcome] = []

        for record in records {
            do {
                let existing = try await existingSet(managedZone: managedZone, name: record.name,
                                                     type: record.type.rawValue, token: token)
                guard let values = record.updatedSet(existing: existing?.values ?? [],
                                                     target: { self.target(for: $0) }) else {
                    outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    continue
                }
                try await changeRecordSet(managedZone: managedZone, name: record.name,
                                          type: record.type.rawValue, ttl: existing?.ttl ?? 300,
                                          values: values, existing: existing, token: token)
                outcomes.append(DNSPublishOutcome(record: record,
                                                  result: existing == nil ? .created : .updated))
            } catch let error as GoogleCloudDNSError {
                outcomes.append(DNSPublishOutcome(record: record, result: .failed(error.message)))
            }
        }
        return outcomes
    }

    // MARK: - Zone lookup

    private func managedZoneName(for zone: String, token: String) async throws -> String {
        let target = normalizedZoneName(zone)
        var pageToken: String?
        repeat {
            var query = ["maxResults": "200"]
            if let pageToken { query["pageToken"] = pageToken }
            let data = try await send(.get, path: "projects/\(projectID)/managedZones",
                                      query: query, token: token)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw GoogleCloudDNSError.unreadableResponse(status: 200)
            }
            let zones = object["managedZones"] as? [[String: Any]] ?? []
            for entry in zones {
                if let dnsName = entry["dnsName"] as? String, let name = entry["name"] as? String,
                   normalizedZoneName(dnsName) == target {
                    return name
                }
            }
            pageToken = object["nextPageToken"] as? String
        } while pageToken != nil
        throw GoogleCloudDNSError.zoneNotFound(zone)
    }

    private func normalizedZoneName(_ name: String) -> String {
        (name.hasSuffix(".") ? String(name.dropLast()) : name).lowercased()
    }

    // MARK: - Naming and values

    private func target(for record: DNSRecord) -> String {
        switch record.type {
        case .mx:
            let host = record.value.hasSuffix(".") ? record.value : record.value + "."
            return "\(record.priority ?? 0) \(host)"
        case .srv:
            guard let srv = record.srv else { return record.value }
            let host = srv.target.hasSuffix(".") ? srv.target : srv.target + "."
            return "\(srv.priority) \(srv.weight) \(srv.port) \(host)"
        case .a, .aaaa:
            return record.value
        case .txt:
            return bindTXTRData(record.value)
        }
    }

    private func normalized(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    // MARK: - Existing records

    private func existingSet(managedZone: String, name: String, type: String,
                             token: String) async throws -> (ttl: Int, values: [String])? {
        let fqdn = name.hasSuffix(".") ? name : name + "."
        let data = try await send(.get,
                                  path: "projects/\(projectID)/managedZones/\(managedZone)/rrsets",
                                  query: ["name": fqdn, "type": type], token: token)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sets = object["rrsets"] as? [[String: Any]],
              let match = sets.first(where: { ($0["type"] as? String) == type }) else {
            return nil
        }
        return (match["ttl"] as? Int ?? 300, match["rrdatas"] as? [String] ?? [])
    }

    private func changeRecordSet(managedZone: String, name: String, type: String, ttl: Int,
                                 values: [String], existing: (ttl: Int, values: [String])?,
                                 token: String) async throws {
        let fqdn = name.hasSuffix(".") ? name : name + "."
        var change: [String: Any] = [
            "additions": [["name": fqdn, "type": type, "ttl": ttl, "rrdatas": values]],
        ]
        if let existing, !existing.values.isEmpty {
            change["deletions"] = [["name": fqdn, "type": type, "ttl": existing.ttl,
                                    "rrdatas": existing.values]]
        }
        _ = try await send(.post,
                           path: "projects/\(projectID)/managedZones/\(managedZone)/changes",
                           body: change, token: token)
    }

    // MARK: - OAuth2: service-account JWT → access token

    private func accessToken() async throws -> String {
        let jwt = try signedJWT(now: clock())
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=\(Self.formEncode("urn:ietf:params:oauth:grant-type:jwt-bearer"))"
            + "&assertion=\(Self.formEncode(jwt))"
        request.httpBody = Data(body.utf8)

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw GoogleCloudDNSError.from(status: status, body: data)
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = object["access_token"] as? String else {
            throw GoogleCloudDNSError.unreadableResponse(status: status)
        }
        return token
    }

    private func signedJWT(now: Date) throws -> String {
        guard let key = Self.rsaPrivateKey(fromPEM: privateKeyPEM) else {
            throw GoogleCloudDNSError.signingFailed
        }
        let iat = Int(now.timeIntervalSince1970)
        let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": clientEmail, "scope": Self.scope, "aud": tokenURI,
            "iat": iat, "exp": iat + 3600,
        ]
        let signingInput = try "\(Self.base64URL(json: header)).\(Self.base64URL(json: claims))"

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData, &error) as Data? else {
            throw GoogleCloudDNSError.signingFailed
        }
        return "\(signingInput).\(Self.base64URLEncode(signature))"
    }

    private static func base64URL(json: [String: Any]) throws -> String {
        base64URLEncode(try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func rsaPrivateKey(fromPEM pem: String) -> SecKey? {
        let isPKCS1 = pem.contains("BEGIN RSA PRIVATE KEY")
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: stripped) else { return nil }
        let pkcs1 = isPKCS1 ? der : (DERReader.pkcs1FromPKCS8(der) ?? der)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST" }

    @discardableResult
    private func send(_ method: Method, path: String, query: [String: String] = [:],
                      body: [String: Any]? = nil, token: String) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw GoogleCloudDNSError.badRequest(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw GoogleCloudDNSError.from(status: status, body: data)
        }
        return data
    }
}

// MARK: - Minimal DER reader

enum DERReader {
    struct Element { let tag: UInt8; let range: Range<Int> }

    /// Reads one tag-length-value at `offset`
    static func readElement(_ bytes: [UInt8], at offset: Int) -> (element: Element, next: Int)? {
        guard offset + 1 < bytes.count else { return nil }
        let tag = bytes[offset]
        let first = bytes[offset + 1]
        var contentStart = offset + 2
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let lengthBytes = Int(first & 0x7F)
            guard offset + 2 + lengthBytes <= bytes.count else { return nil }
            for i in 0..<lengthBytes { length = (length << 8) | Int(bytes[offset + 2 + i]) }
            contentStart = offset + 2 + lengthBytes
        }
        let range = contentStart..<(contentStart + length)
        guard range.upperBound <= bytes.count else { return nil }
        return (Element(tag: tag, range: range), range.upperBound)
    }

    static func pkcs1FromPKCS8(_ der: Data) -> Data? {
        let bytes = [UInt8](der)
        guard let (outer, _) = readElement(bytes, at: 0), outer.tag == 0x30 else { return nil }
        var cursor = outer.range.lowerBound
        guard let (_, afterVersion) = readElement(bytes, at: cursor) else { return nil }
        cursor = afterVersion
        guard let (_, afterAlgorithm) = readElement(bytes, at: cursor) else { return nil }
        cursor = afterAlgorithm
        guard let (keyElement, _) = readElement(bytes, at: cursor), keyElement.tag == 0x04 else { return nil }
        return Data(bytes[keyElement.range])
    }
}

// MARK: - Transport seam

public protocol GoogleCloudDNSHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionGoogleCloudDNSHTTPClient: GoogleCloudDNSHTTPClient {
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

// MARK: - Errors

public enum GoogleCloudDNSError: Error, LocalizedError, Hashable {
    case malformedToken
    case signingFailed
    case invalidToken
    case zoneNotFound(String)
    case api(status: Int, message: String)
    case unreadableResponse(status: Int)
    case badRequest(String)

    static func from(status: Int, body: Data) -> GoogleCloudDNSError {
        if status == 401 || status == 403 { return .invalidToken }
        return .api(status: status, message: errorMessage(in: body) ?? "HTTP \(status)")
    }

    private static func errorMessage(in body: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let description = object["error_description"] as? String { return description }
        if let error = object["error"] as? String { return error }
        return nil
    }

    public var message: String {
        switch self {
        case .malformedToken:
            return "Paste the full service-account JSON key"
        case .signingFailed:
            return "could not sign the request with this private key"
        case .invalidToken:
            return "invalid or unauthorized service-account credentials"
        case .zoneNotFound(let zone):
            return "no managed zone for \(zone) in this project"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .unreadableResponse(let status):
            return "unreadable response from Google Cloud DNS (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

import CryptoKit
import Foundation

public struct Route53DNSProvider: DNSPublishingProvider {
    public let displayName = "Amazon Route 53"

    private let accessKeyID: String
    private let secretAccessKey: String
    private let http: any Route53HTTPClient
    private let baseURL: URL
    private let clock: @Sendable () -> Date

    private static let region = "us-east-1"
    private static let service = "route53"

    public init(token: String,
                http: any Route53HTTPClient = URLSessionRoute53HTTPClient(),
                baseURL: URL = URL(string: "https://route53.amazonaws.com")!,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        if let colon = token.firstIndex(of: ":") {
            self.accessKeyID = String(token[token.startIndex..<colon])
            self.secretAccessKey = String(token[token.index(after: colon)...])
        } else {
            self.accessKeyID = token
            self.secretAccessKey = ""
        }
        self.http = http
        self.baseURL = baseURL
        self.clock = clock
    }

    private var hasKeys: Bool { !accessKeyID.isEmpty && !secretAccessKey.isEmpty }

    // MARK: - Public surface

    /// Confirms the credentials work before anything is written
    public func verifyToken() async throws {
        guard hasKeys else { throw Route53Error.malformedToken }
        _ = try await send(.get, path: "/2013-04-01/hostedzone")
    }

    public func apply(_ records: [DNSRecord], zone: String) async throws {
        _ = try await publishReportingOutcomes(records, zone: zone)
    }

    @discardableResult
    public func publishReportingOutcomes(_ records: [DNSRecord],
                                         zone: String) async throws -> [DNSPublishOutcome] {
        guard hasKeys else { throw Route53Error.malformedToken }
        let zoneID = try await zoneID(for: zone)
        var outcomes: [DNSPublishOutcome] = []

        for record in records {
            do {
                let existing = try await existingSet(zoneID: zoneID, name: record.name,
                                                     type: record.type.rawValue)
                guard let values = record.updatedSet(existing: existing?.values ?? [],
                                                     target: { self.target(for: $0) }) else {
                    outcomes.append(DNSPublishOutcome(record: record, result: .unchanged))
                    continue
                }
                try await changeRecordSet(zoneID: zoneID, name: record.name,
                                          type: record.type.rawValue,
                                          ttl: existing?.ttl ?? 300, values: values)
                outcomes.append(DNSPublishOutcome(record: record,
                                                  result: existing == nil ? .created : .updated))
            } catch let error as Route53Error {
                outcomes.append(DNSPublishOutcome(record: record, result: .failed(error.message)))
            }
        }
        return outcomes
    }

    // MARK: - Zone lookup

    private func zoneID(for zone: String) async throws -> String {
        let data = try await send(.get, path: "/2013-04-01/hostedzonesbyname",
                                  query: ["dnsname": zone])
        let parsed = Route53ZoneListParser.parse(data)
        guard let first = parsed.first,
              normalizedZoneName(first.name) == zone.lowercased() else {
            throw Route53Error.zoneNotFound(zone)
        }
        return first.id.replacingOccurrences(of: "/hostedzone/", with: "")
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

    private func existingSet(zoneID: String, name: String, type: String) async throws -> (ttl: Int, values: [String])? {
        let data = try await send(.get, path: "/2013-04-01/hostedzone/\(zoneID)/rrset",
                                  query: ["name": name, "type": type, "maxitems": "1"])
        guard let set = Route53RecordSetParser.parse(data).first,
              set.type == type, normalizedZoneName(set.name) == normalizedZoneName(name) else {
            return nil
        }
        return (set.ttl, set.values)
    }

    private func changeRecordSet(zoneID: String, name: String, type: String,
                                 ttl: Int, values: [String]) async throws {
        let records = values.map { "<ResourceRecord><Value>\(xmlEscape($0))</Value></ResourceRecord>" }
            .joined()
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
        <ChangeBatch><Changes><Change><Action>UPSERT</Action><ResourceRecordSet>\
        <Name>\(xmlEscape(name))</Name><Type>\(type)</Type><TTL>\(ttl)</TTL>\
        <ResourceRecords>\(records)</ResourceRecords></ResourceRecordSet></Change></Changes></ChangeBatch>
        </ChangeResourceRecordSetsRequest>
        """
        _ = try await send(.post, path: "/2013-04-01/hostedzone/\(zoneID)/rrset", body: body)
    }

    private func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Transport + SigV4

    private enum Method: String { case get = "GET", post = "POST" }

    @discardableResult
    private func send(_ method: Method, path: String,
                      query: [String: String] = [:], body: String? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        let sortedQuery = query.sorted { $0.key < $1.key }
        if !sortedQuery.isEmpty {
            components?.percentEncodedQueryItems = sortedQuery.map {
                URLQueryItem(name: Self.awsURIEncode($0.key), value: Self.awsURIEncode($0.value))
            }
        }
        guard let url = components?.url else { throw Route53Error.badRequest(path) }

        let bodyData = Data((body ?? "").utf8)
        let payloadHash = Self.hex(SHA256.hash(data: bodyData))
        let now = clock()
        let amzDate = Self.dateFormatter.string(from: now)
        let dateStamp = String(amzDate.prefix(8))
        let host = url.host ?? ""

        var headers = ["host": host, "x-amz-date": amzDate]
        if body != nil { headers["content-type"] = "application/xml" }
        let signedHeaderNames = headers.keys.sorted()
        let canonicalHeaders = signedHeaderNames.map { "\($0):\(headers[$0]!)\n" }.joined()
        let signedHeaders = signedHeaderNames.joined(separator: ";")

        let canonicalURI = Self.awsURIEncodePath(url.path.isEmpty ? "/" : url.path)
        let canonicalQuery = (components?.percentEncodedQueryItems ?? [])
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")

        let canonicalRequest = [
            method.rawValue, canonicalURI, canonicalQuery,
            canonicalHeaders, signedHeaders, payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(Self.region)/\(Self.service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256", amzDate, scope,
            Self.hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
        ].joined(separator: "\n")

        let signingKey = Self.signingKey(secret: secretAccessKey, dateStamp: dateStamp)
        let signature = Self.hex(HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8), using: signingKey))

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw Route53Error.from(status: status, body: data)
        }
        return data
    }

    private static func signingKey(secret: String, dateStamp: String) -> SymmetricKey {
        func hmac(_ key: SymmetricKey, _ data: String) -> SymmetricKey {
            SymmetricKey(data: HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key))
        }
        let kSecret = SymmetricKey(data: Data("AWS4\(secret)".utf8))
        let kDate = hmac(kSecret, dateStamp)
        let kRegion = hmac(kDate, region)
        let kService = hmac(kRegion, service)
        return hmac(kService, "aws4_request")
    }

    private static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func awsURIEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func awsURIEncodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { awsURIEncode(String($0)) }
            .joined(separator: "/")
    }
}

// MARK: - Transport seam

public protocol Route53HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionRoute53HTTPClient: Route53HTTPClient {
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

// MARK: - XML parsing

final class Route53ZoneListParser: NSObject, XMLParserDelegate {
    private var zones: [(id: String, name: String)] = []
    private var currentID = ""
    private var currentName = ""
    private var inZone = false
    private var currentElement = ""

    static func parse(_ data: Data) -> [(id: String, name: String)] {
        let delegate = Route53ZoneListParser()
        let xml = XMLParser(data: data)
        xml.delegate = delegate
        xml.parse()
        return delegate.zones
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
               qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = name
        if name == "HostedZone" { inZone = true; currentID = ""; currentName = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inZone else { return }
        if currentElement == "Id" { currentID += string }
        if currentElement == "Name" { currentName += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
               qualifiedName: String?) {
        if name == "HostedZone" {
            zones.append((currentID, currentName))
            inZone = false
        }
    }
}

/// `ListResourceRecordSets`' `ResourceRecordSets/ResourceRecordSet` — `Name`, `Type`, `TTL`, and every `ResourceRecords/ResourceRecord/Value`
final class Route53RecordSetParser: NSObject, XMLParserDelegate {
    private var sets: [(name: String, type: String, ttl: Int, values: [String])] = []
    private var name = "", type = "", ttlText = ""
    private var values: [String] = []
    private var currentValue = ""
    private var currentElement = ""
    private var inSet = false

    static func parse(_ data: Data) -> [(name: String, type: String, ttl: Int, values: [String])] {
        let delegate = Route53RecordSetParser()
        let xml = XMLParser(data: data)
        xml.delegate = delegate
        xml.parse()
        return delegate.sets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
               qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "ResourceRecordSet" {
            inSet = true; name = ""; type = ""; ttlText = ""; values = []
        }
        if elementName == "ResourceRecord" { currentValue = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inSet else { return }
        switch currentElement {
        case "Name": name += string
        case "Type": type += string
        case "TTL": ttlText += string
        case "Value": currentValue += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
               qualifiedName: String?) {
        if elementName == "ResourceRecord" { values.append(currentValue) }
        if elementName == "ResourceRecordSet" {
            sets.append((name, type, Int(ttlText) ?? 300, values))
            inSet = false
        }
    }
}

// MARK: - Errors

/// Route 53 answers a failure with `<ErrorResponse><Error><Code>
public enum Route53Error: Error, LocalizedError, Hashable {
    case malformedToken
    case invalidToken
    case zoneNotFound(String)
    case api(status: Int, message: String)
    case unreadableResponse(status: Int)
    case badRequest(String)

    static func from(status: Int, body: Data) -> Route53Error {
        if status == 403 { return .invalidToken }
        let message = Route53Error.errorMessage(in: body) ?? "HTTP \(status)"
        return .api(status: status, message: message)
    }

    private static func errorMessage(in body: Data) -> String? {
        guard let text = String(data: body, encoding: .utf8),
              let start = text.range(of: "<Message>"),
              let end = text.range(of: "</Message>") else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    public var message: String {
        switch self {
        case .malformedToken:
            return "Paste both keys as accessKeyID:secretAccessKey"
        case .invalidToken:
            return "Invalid access key or secret key"
        case .zoneNotFound(let zone):
            return "no hosted zone named \(zone) in this account"
        case .api(let status, let message):
            return "\(message) (HTTP \(status))"
        case .unreadableResponse(let status):
            return "unreadable response from Route 53 (HTTP \(status))"
        case .badRequest(let path):
            return "could not build a request for \(path)"
        }
    }

    public var errorDescription: String? { message }
}

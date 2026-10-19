import CryptoKit
import XCTest
@testable import gryonixNexusCore

final class Route53DNSProviderTests: XCTestCase {
    private final class StubClient: Route53HTTPClient, @unchecked Sendable {
        struct Sent {
            let method: String
            let url: String
            let headers: [String: String]
            let body: String?
        }

        private let lock = NSLock()
        private var responses: [(Data, Int)]
        private(set) var sent: [Sent] = []

        init(responses: [(String, Int)]) {
            self.responses = responses.map { (Data($0.0.utf8), $0.1) }
        }

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            lock.lock(); defer { lock.unlock() }
            sent.append(Sent(method: request.httpMethod ?? "",
                             url: request.url?.absoluteString ?? "",
                             headers: request.allHTTPHeaderFields ?? [:],
                             body: request.httpBody.map { String(decoding: $0, as: UTF8.self) }))
            guard !responses.isEmpty else { return (Data("<Error/>".utf8), 500) }
            return responses.removeFirst()
        }
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func provider(_ responses: [(String, Int)],
                          token: String = "AKIAEXAMPLE:secretkeyexample")
        -> (Route53DNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        let provider = Route53DNSProvider(
            token: token, http: client,
            baseURL: URL(string: "https://route53.amazonaws.com")!,
            clock: { Self.fixedNow })
        return (provider, client)
    }

    private func zoneList(id: String = "/hostedzone/Z1PA6795UKMFR9", name: String = "example.com.") -> String {
        """
        <?xml version="1.0"?>
        <ListHostedZonesByNameResponse><HostedZones><HostedZone>\
        <Id>\(id)</Id><Name>\(name)</Name><CallerReference>x</CallerReference>\
        </HostedZone></HostedZones><IsTruncated>false</IsTruncated></ListHostedZonesByNameResponse>
        """
    }

    private func emptyRecordSets() -> String {
        """
        <?xml version="1.0"?>
        <ListResourceRecordSetsResponse><ResourceRecordSets/><IsTruncated>false</IsTruncated>\
        </ListResourceRecordSetsResponse>
        """
    }

    private func recordSet(name: String, type: String, ttl: Int, values: [String]) -> String {
        let recs = values.map { "<ResourceRecord><Value>\($0)</Value></ResourceRecord>" }.joined()
        return """
        <?xml version="1.0"?>
        <ListResourceRecordSetsResponse><ResourceRecordSets><ResourceRecordSet>\
        <Name>\(name)</Name><Type>\(type)</Type><TTL>\(ttl)</TTL>\
        <ResourceRecords>\(recs)</ResourceRecords></ResourceRecordSet></ResourceRecordSets>\
        <IsTruncated>false</IsTruncated></ListResourceRecordSetsResponse>
        """
    }

    private let changeOK = """
    <?xml version="1.0"?>
    <ChangeResourceRecordSetsResponse><ChangeInfo><Id>x</Id><Status>PENDING</Status>\
    </ChangeInfo></ChangeResourceRecordSetsResponse>
    """

    private func ok(_ body: String) -> (String, Int) { (body, 200) }

    // MARK: - Auth

    func testAMissingColonIsRefusedBeforeAnyRequest() async throws {
        let (provider, client) = provider([], token: "no-colon-here")
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as Route53Error {
            XCTAssertEqual(error, .malformedToken)
        }
        XCTAssertTrue(client.sent.isEmpty, "a malformed token must not reach the network")
    }

    func testVerifyTokenListsZonesAndWritesNothing() async throws {
        let (provider, client) = provider([("<ListHostedZonesResponse/>", 200)])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["GET"])
        XCTAssertEqual(client.sent.first?.url, "https://route53.amazonaws.com/2013-04-01/hostedzone")
    }

    func testTheAuthorizationHeaderCarriesTheCredentialScopeAndSignedHeaders() async throws {
        let (provider, client) = provider([("<ListHostedZonesResponse/>", 200)])
        try await provider.verifyToken()
        let auth = try XCTUnwrap(client.sent.first?.headers["Authorization"])
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20231114/us-east-1/route53/aws4_request, "),
                     "unexpected credential scope: \(auth)")
        XCTAssertTrue(auth.contains("SignedHeaders=host;x-amz-date, "), "unexpected signed headers: \(auth)")
        let signature = auth.components(separatedBy: "Signature=").last ?? ""
        XCTAssertEqual(signature.count, 64, "a SHA256 HMAC hex-encodes to 64 characters: \(signature)")
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                     "the signature must be lowercase hex: \(signature)")
    }

    func testTheSignatureMatchesAnIndependentComputation() async throws {
        let (provider, client) = provider([("<ListHostedZonesResponse/>", 200)])
        try await provider.verifyToken()
        let request = try XCTUnwrap(client.sent.first)
        let amzDate = try XCTUnwrap(request.headers["X-Amz-Date"])
        let dateStamp = String(amzDate.prefix(8))

        let payloadHash = sha256Hex("")
        let canonicalHeaders = "host:route53.amazonaws.com\nx-amz-date:\(amzDate)\n"
        let canonicalRequest = [
            "GET", "/2013-04-01/hostedzone", "", canonicalHeaders, "host;x-amz-date", payloadHash,
        ].joined(separator: "\n")
        let scope = "\(dateStamp)/us-east-1/route53/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(canonicalRequest),
        ].joined(separator: "\n")

        func hmac(_ key: SymmetricKey, _ data: String) -> SymmetricKey {
            SymmetricKey(data: HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key))
        }
        let kSecret = SymmetricKey(data: Data("AWS4secretkeyexample".utf8))
        let kDate = hmac(kSecret, dateStamp)
        let kRegion = hmac(kDate, "us-east-1")
        let kService = hmac(kRegion, "route53")
        let kSigning = hmac(kService, "aws4_request")
        let expected = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: kSigning)
            .map { String(format: "%02x", $0) }.joined()

        let auth = try XCTUnwrap(request.headers["Authorization"])
        let actual = auth.components(separatedBy: "Signature=").last ?? ""
        XCTAssertEqual(actual, expected)
    }

    private func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func testAForbiddenAnswerIsReportedAsAnInvalidToken() async throws {
        let (provider, _) = provider([("<ErrorResponse/>", 403)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as Route53Error {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Zone lookup

    func testAZoneNameThatDoesNotMatchIsReportedAsNotFound() async throws {
        let (provider, _) = provider([(zoneList(name: "example.org."), 200)])
        do {
            _ = try await provider.publishReportingOutcomes(
                [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
                zone: "example.com")
            XCTFail("expected an error")
        } catch let error as Route53Error {
            XCTAssertEqual(error, .zoneNotFound("example.com"))
        }
    }

    func testTheHostedZoneIdPrefixIsStripped() async throws {
        let (provider, client) = provider([
            ok(zoneList(id: "/hostedzone/Z1PA6795UKMFR9")),
            ok(emptyRecordSets()),
            ok(changeOK),
        ])
        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")
        XCTAssertTrue(client.sent.contains { $0.url.contains("/hostedzone/Z1PA6795UKMFR9/rrset") },
                     "expected the bare zone id in the rrset path: \(client.sent.map(\.url))")
        XCTAssertFalse(client.sent.contains { $0.url.contains("hostedzone//hostedzone") })
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedWithOneValue() async throws {
        let (provider, client) = provider([ok(zoneList()), ok(emptyRecordSets()), ok(changeOK)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let change = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(change.method, "POST")
        XCTAssertTrue(change.url.hasSuffix("/rrset"))
        let body = try XCTUnwrap(change.body)
        XCTAssertTrue(body.contains("<Action>UPSERT</Action>"))
        XCTAssertTrue(body.contains("<Name>mail.example.com</Name>"))
        XCTAssertTrue(body.contains("<Value>203.0.113.4</Value>"))
    }

    func testAnExistingSingleValueMatchIsUnchangedAndNothingIsWritten() async throws {
        let (provider, client) = provider([
            ok(zoneList()),
            ok(recordSet(name: "mail.example.com.", type: "A", ttl: 300, values: ["203.0.113.4"])),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 2, "unchanged must not call ChangeResourceRecordSets")
    }

    func testAnExistingMultiValueSetKeepsItsOtherValuesOnUpdate() async throws {
        let (provider, client) = provider([
            ok(zoneList()),
            ok(recordSet(name: "example.com.", type: "A", ttl: 300, values: ["198.51.100.1", "198.51.100.2"])),
            ok(changeOK),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "198.51.100.3")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        let body = try XCTUnwrap(client.sent.last?.body)
        for value in ["198.51.100.1", "198.51.100.2", "198.51.100.3"] {
            XCTAssertTrue(body.contains("<Value>\(value)</Value>"), "missing \(value) in: \(body)")
        }
    }

    func testAValueAlreadyInAMultiValueSetIsUnchanged() async throws {
        let (provider, client) = provider([
            ok(zoneList()),
            ok(recordSet(name: "example.com.", type: "A", ttl: 300, values: ["198.51.100.1", "198.51.100.2"])),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "198.51.100.2")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 2)
    }

    func testAnMXRecordFoldsThePriorityIntoTheValue() async throws {
        let (provider, client) = provider([ok(zoneList()), ok(emptyRecordSets()), ok(changeOK)])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        let body = try XCTUnwrap(client.sent.last?.body)
        XCTAssertTrue(body.contains("<Value>10 mail.example.com.</Value>"))
    }

    func testATXTRecordIsSentQuoted() async throws {
        let (provider, client) = provider([ok(zoneList()), ok(emptyRecordSets()), ok(changeOK)])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .txt, value: "v=spf1 -all")], zone: "example.com")

        let body = try XCTUnwrap(client.sent.last?.body)
        XCTAssertTrue(body.contains("<Value>&quot;v=spf1 -all&quot;</Value>")
                     || body.contains("<Value>\"v=spf1 -all\"</Value>"),
                     "expected a quoted TXT value in: \(body)")
    }

    func testAMissingZoneIsNamedInTheError() async throws {
        let (provider, _) = provider([("<ListHostedZonesByNameResponse><HostedZones/></ListHostedZonesByNameResponse>", 200)])

        do {
            _ = try await provider.publishReportingOutcomes(
                [DNSRecord(name: "mail.nope.com", type: .a, value: "203.0.113.4")], zone: "nope.com")
            XCTFail("expected an error")
        } catch let error as Route53Error {
            XCTAssertEqual(error, .zoneNotFound("nope.com"))
        }
    }
}

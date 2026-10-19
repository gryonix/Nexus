import CryptoKit
import XCTest
@testable import gryonixNexusCore

final class OVHDNSProviderTests: XCTestCase {
    private final class StubClient: OVHHTTPClient, @unchecked Sendable {
        struct Sent {
            let method: String
            let url: String
            let headers: [String: String]
            let body: [String: Any]?
        }

        private let lock = NSLock()
        private var responses: [(Data, Int)]
        private(set) var sent: [Sent] = []

        init(responses: [(String, Int)]) {
            self.responses = responses.map { (Data($0.0.utf8), $0.1) }
        }

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            lock.lock(); defer { lock.unlock() }
            let body = request.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            sent.append(Sent(method: request.httpMethod ?? "",
                             url: request.url?.absoluteString ?? "",
                             headers: request.allHTTPHeaderFields ?? [:],
                             body: body))
            guard !responses.isEmpty else { return (Data("{}".utf8), 500) }
            return responses.removeFirst()
        }
    }

    private static let serverNow = 1_700_000_000
    private static let localNow = 1_699_999_990

    private func provider(_ responses: [(String, Int)],
                          token: String = "APPKEY:APPSECRET:CONSUMER")
        -> (OVHDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        let provider = OVHDNSProvider(
            token: token, http: client,
            baseURL: URL(string: "https://api.example.test/1.0")!,
            clock: { Date(timeIntervalSince1970: TimeInterval(Self.localNow)) })
        return (provider, client)
    }

    private func ok(_ body: String) -> (String, Int) { (body, 200) }
    private let time = ("1700000000", 200)
    private let nullOK = ("null", 200)
    private let noRecords = "[]"

    private func signature(secret: String = "APPSECRET", consumer: String = "CONSUMER",
                           method: String, url: String, body: String = "",
                           timestamp: String = "1700000000") -> String {
        let base = [secret, consumer, method, url, body, timestamp].joined(separator: "+")
        let digest = Insecure.SHA1.hash(data: Data(base.utf8))
        return "$1$" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Auth

    func testFewerThanThreeKeysIsRefusedBeforeAnyRequest() async throws {
        let (provider, client) = provider([], token: "APPKEY:APPSECRET")
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as OVHError {
            XCTAssertEqual(error, .malformedToken)
        }
        XCTAssertTrue(client.sent.isEmpty, "a malformed token must not reach the network")
    }

    func testAColonInsideTheConsumerKeyStaysInIt() async throws {
        let (provider, client) = provider([time, ok("[]")], token: "AK:AS:CK:with:colons")
        try await provider.verifyToken()
        let verify = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(verify.headers["X-Ovh-Application"], "AK")
        XCTAssertEqual(verify.headers["X-Ovh-Signature"],
                       signature(secret: "AS", consumer: "CK:with:colons",
                                 method: "GET", url: verify.url))
    }

    func testVerifyTokenListsZonesAndWritesNothing() async throws {
        let (provider, client) = provider([time, ok("[\"example.com\"]")])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["GET", "GET"])
        XCTAssertEqual(client.sent.first?.url, "https://api.example.test/1.0/auth/time")
        XCTAssertEqual(client.sent.last?.url, "https://api.example.test/1.0/domain/zone")
    }

    func testASignedRequestCarriesTheFourHeaders() async throws {
        let (provider, client) = provider([time, ok("[\"example.com\"]")])
        try await provider.verifyToken()
        let verify = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(verify.headers["X-Ovh-Application"], "APPKEY")
        XCTAssertEqual(verify.headers["X-Ovh-Consumer"], "CONSUMER")
        XCTAssertEqual(verify.headers["X-Ovh-Timestamp"], "1700000000")
        XCTAssertEqual(verify.headers["X-Ovh-Signature"],
                       signature(method: "GET", url: verify.url))
        // The unauthenticated /auth/time call is not signed.
        XCTAssertNil(client.sent.first?.headers["X-Ovh-Signature"])
    }

    func testAForbiddenAnswerIsReportedAsAnInvalidToken() async throws {
        let (provider, _) = provider([time, ("{\"message\":\"Invalid signature\"}", 403)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as OVHError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedRelativeAndTheZoneIsRefreshed() async throws {
        let (provider, client) = provider([time, ok(noRecords),
                                           ok("{\"id\":1,\"target\":\"203.0.113.4\"}"), nullOK])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        // auth/time, the filtered list, the create, then the refresh.
        XCTAssertEqual(client.sent.map(\.method), ["GET", "GET", "POST", "POST"])
        let list = client.sent[1]
        XCTAssertEqual(list.url,
                       "https://api.example.test/1.0/domain/zone/example.com/record?fieldType=A&subDomain=mail")
        let create = client.sent[2]
        XCTAssertEqual(create.url, "https://api.example.test/1.0/domain/zone/example.com/record")
        XCTAssertEqual(create.body?["fieldType"] as? String, "A")
        XCTAssertEqual(create.body?["subDomain"] as? String, "mail")
        XCTAssertEqual(create.body?["target"] as? String, "203.0.113.4")
        XCTAssertEqual(client.sent.last?.url,
                       "https://api.example.test/1.0/domain/zone/example.com/refresh")
    }

    func testAnApexRecordHasABlankSubdomain() async throws {
        let (provider, client) = provider([time, ok(noRecords),
                                           ok("{\"id\":1}"), nullOK])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent[2].body?["subDomain"] as? String, "")
        XCTAssertEqual(client.sent[1].url,
                       "https://api.example.test/1.0/domain/zone/example.com/record?fieldType=A&subDomain=")
    }

    func testAnMXRecordFoldsThePriorityIntoTheTarget() async throws {
        let (provider, client) = provider([time, ok(noRecords), ok("{\"id\":1}"), nullOK])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        XCTAssertEqual(client.sent[2].body?["target"] as? String, "10 mail.example.com.")
    }

    func testAChangedRecordIsUpdatedByIdAndRefreshed() async throws {
        let (provider, client) = provider([
            time,
            ok("[42]"),
            ok("{\"id\":42,\"subDomain\":\"mail\",\"fieldType\":\"A\",\"target\":\"198.51.100.9\",\"ttl\":3600}"),
            nullOK,
            nullOK
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        let put = client.sent[3]
        XCTAssertEqual(put.method, "PUT")
        XCTAssertEqual(put.url, "https://api.example.test/1.0/domain/zone/example.com/record/42")
        XCTAssertEqual(put.body?["target"] as? String, "203.0.113.4")
        XCTAssertNil(put.body?["fieldType"], "a PUT changes the value, not the record's type")
        XCTAssertEqual(client.sent.last?.url,
                       "https://api.example.test/1.0/domain/zone/example.com/refresh")
    }

    func testAnIdenticalRecordIsLeftAloneAndNothingIsRefreshed() async throws {
        let (provider, client) = provider([
            time,
            ok("[42]"),
            ok("{\"id\":42,\"target\":\"203.0.113.4\"}")
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 3, "an up-to-date record writes nothing and skips the refresh")
    }

    func testATrailingDotOnAHostTargetDoesNotForceAnUpdate() async throws {
        let (provider, client) = provider([
            time,
            ok("[7]"),
            ok("{\"id\":7,\"target\":\"1 mail.example.com\"}")
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 1)],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
    }

    func testAMissingZoneIsNamedInTheError() async throws {
        let (provider, _) = provider([time, ("{\"message\":\"This service does not exist\"}", 404)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.nope.com", type: .a, value: "203.0.113.4")],
            zone: "nope.com")

        guard case .failed(let message) = outcomes.first?.result else {
            return XCTFail("expected a per-record failure")
        }
        XCTAssertTrue(message.contains("nope.com"), "the missing zone should be named: \(message)")
    }
}

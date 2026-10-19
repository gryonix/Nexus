import XCTest
@testable import gryonixNexusCore

final class PorkbunDNSProviderTests: XCTestCase {
    private final class StubClient: PorkbunHTTPClient, @unchecked Sendable {
        struct Sent {
            let method: String
            let url: String
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
                             body: body))
            guard !responses.isEmpty else { return (Data("{}".utf8), 500) }
            return responses.removeFirst()
        }
    }

    private func provider(_ responses: [(String, Int)],
                          token: String = "test-key:test-secret") -> (PorkbunDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        return (PorkbunDNSProvider(token: token, http: client,
                                   baseURL: URL(string: "https://api.example.test/v3")!),
                client)
    }

    private func ok(_ body: String) -> (String, Int) { (body, 200) }

    private let emptyRecords = "{\"status\":\"SUCCESS\",\"records\":[]}"

    // MARK: - Auth

    func testBothKeysGoUpInTheBody() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")])
        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")
        XCTAssertEqual(client.sent.first?.body?["apikey"] as? String, "test-key")
        XCTAssertEqual(client.sent.first?.body?["secretapikey"] as? String, "test-secret")
    }

    func testAColonInsideTheSecretStaysInTheSecret() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")],
                                          token: "key:secret:with:colons")
        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")
        XCTAssertEqual(client.sent.first?.body?["apikey"] as? String, "key")
        XCTAssertEqual(client.sent.first?.body?["secretapikey"] as? String, "secret:with:colons")
    }

    func testAMissingColonIsRefusedBeforeAnyRequest() async throws {
        let (provider, client) = provider([], token: "just-one-value")
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as PorkbunError {
            XCTAssertEqual(error, .malformedToken)
        }
        XCTAssertTrue(client.sent.isEmpty, "a malformed token must not reach the network")
    }

    func testVerifyTokenPingsAndWritesNothing() async throws {
        let (provider, client) = provider([ok("{\"status\":\"SUCCESS\",\"yourIp\":\"203.0.113.1\",\"credentialsValid\":true}")])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["POST"])
        XCTAssertEqual(client.sent.first?.url, "https://api.example.test/v3/ping")
    }

    func testAnInvalidTokenIsReportedPlainly() async throws {
        let (provider, _) = provider([("{\"status\":\"ERROR\",\"message\":\"Invalid API key.\"}", 400)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as PorkbunError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedWithARelativeName() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.url, "https://api.example.test/v3/dns/create/example.com")
        XCTAssertEqual(create.body?["type"] as? String, "A")
        XCTAssertEqual(create.body?["name"] as? String, "mail")
        XCTAssertEqual(create.body?["content"] as? String, "203.0.113.4")
    }

    /// Porkbun's own convention — "blank for root
    func testAnApexRecordIsNamedBlank() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["name"] as? String, "")
    }

    func testAnMXRecordSendsPriorityAsItsOwnField() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        let sent = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(sent.body?["content"] as? String, "mail.example.com.")
        XCTAssertEqual(sent.body?["prio"] as? Int, 10)
    }

    func testAnSRVRecordSendsTheTargetAsContentAndPriorityAsPrio() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord.service(name: "_sip._tcp.example.com",
                               srv: .init(priority: 0, weight: 5, port: 5060, target: "sip.example.com"))],
            zone: "example.com")

        let sent = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(sent.body?["content"] as? String, "sip.example.com.")
        XCTAssertEqual(sent.body?["prio"] as? Int, 0)
    }

    func testAChangedRecordIsUpdatedByItsId() async throws {
        let existing = """
        {"status":"SUCCESS","records":[{"id":"rec1","type":"A","name":"mail.example.com","content":"198.51.100.9"}]}
        """
        let (provider, client) = provider([ok(existing), ok("{\"status\":\"SUCCESS\"}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        let edit = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(edit.method, "POST")
        XCTAssertEqual(edit.url, "https://api.example.test/v3/dns/edit/example.com/rec1")
        XCTAssertEqual(edit.body?["content"] as? String, "203.0.113.4")
        XCTAssertEqual(edit.body?["name"] as? String, "mail")
        XCTAssertEqual(edit.body?["type"] as? String, "A")
    }

    func testAnApexUpdateSendsAnEmptyName() async throws {
        let existing = """
        {"status":"SUCCESS","records":[{"id":"rec1","type":"A","name":"example.com","content":"198.51.100.9"}]}
        """
        let (provider, client) = provider([ok(existing), ok("{\"status\":\"SUCCESS\"}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.url, "https://api.example.test/v3/dns/edit/example.com/rec1")
        XCTAssertEqual(client.sent.last?.body?["name"] as? String, "")
    }

    func testAnIdenticalRecordIsLeftAlone() async throws {
        let existing = """
        {"status":"SUCCESS","records":[{"id":"rec1","type":"A","name":"mail.example.com","content":"203.0.113.4"}]}
        """
        let (provider, client) = provider([ok(existing)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 1, "nothing may be written when nothing changed")
    }

    func testMatchingIgnoresAWrongNameSameType() async throws {
        let existing = """
        {"status":"SUCCESS","records":[{"id":"rec1","type":"A","name":"other.example.com","content":"198.51.100.9"}]}
        """
        let (provider, client) = provider([ok(existing), ok("{\"status\":\"SUCCESS\",\"id\":\"1\"}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        XCTAssertEqual(client.sent.last?.url, "https://api.example.test/v3/dns/create/example.com")
    }
}

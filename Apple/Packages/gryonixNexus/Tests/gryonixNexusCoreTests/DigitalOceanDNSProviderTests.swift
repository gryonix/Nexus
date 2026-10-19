import XCTest
@testable import gryonixNexusCore

final class DigitalOceanDNSProviderTests: XCTestCase {
    private final class StubClient: DigitalOceanHTTPClient, @unchecked Sendable {
        struct Sent {
            let method: String
            let url: String
            let authorization: String?
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
                             authorization: request.value(forHTTPHeaderField: "Authorization"),
                             body: body))
            guard !responses.isEmpty else { return (Data("{}".utf8), 500) }
            return responses.removeFirst()
        }
    }

    private func provider(_ responses: [(String, Int)]) -> (DigitalOceanDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        return (DigitalOceanDNSProvider(token: "test-token", http: client,
                                        baseURL: URL(string: "https://api.example.test/v2")!),
                client)
    }

    private func ok(_ body: String) -> (String, Int) { (body, 200) }

    private let emptyRecords = "{\"domain_records\":[]}"

    // MARK: - Auth

    func testTheTokenGoesUpAsABearer() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{}")])
        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")
        XCTAssertEqual(client.sent.first?.authorization, "Bearer test-token")
    }

    func testVerifyTokenReadsAccountAndWritesNothing() async throws {
        let (provider, client) = provider([ok("{\"account\":{\"email\":\"owner@example.com\"}}")])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["GET"])
        XCTAssertEqual(client.sent.first?.url, "https://api.example.test/v2/account")
    }

    func testAnInvalidTokenIsReportedPlainly() async throws {
        let (provider, _) = provider([("{\"id\":\"unauthorized\",\"message\":\"Unable to authenticate\"}", 401)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as DigitalOceanError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedWithARelativeName() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"domain_record\":{}}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.url, "https://api.example.test/v2/domains/example.com/records")
        XCTAssertEqual(create.body?["type"] as? String, "A")
        XCTAssertEqual(create.body?["name"] as? String, "mail")
        XCTAssertEqual(create.body?["data"] as? String, "203.0.113.4")
    }

    func testAnApexRecordIsNamedAt() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"domain_record\":{}}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["name"] as? String, "@")
    }

    func testAnMXTargetCarriesATrailingDot() async throws {
        let (provider, client) = provider([ok(emptyRecords), ok("{\"domain_record\":{}}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["data"] as? String, "mail.example.com.")
        XCTAssertEqual(client.sent.last?.body?["priority"] as? Int, 10)
    }

    func testAChangedRecordIsUpdatedInPlace() async throws {
        let existing = """
        {"domain_records":[{"id":42,"type":"A","name":"mail","data":"198.51.100.9"}]}
        """
        let (provider, client) = provider([ok(existing), ok("{\"domain_record\":{}}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        XCTAssertEqual(client.sent.last?.method, "PUT")
        XCTAssertEqual(client.sent.last?.url,
                       "https://api.example.test/v2/domains/example.com/records/42")
    }

    func testAnIdenticalRecordIsLeftAlone() async throws {
        let existing = """
        {"domain_records":[{"id":42,"type":"A","name":"mail","data":"203.0.113.4"}]}
        """
        let (provider, client) = provider([ok(existing)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 1, "nothing may be written when nothing changed")
    }

    func testOneRejectedRecordDoesNotAbandonTheRest() async throws {
        let (provider, _) = provider([
            ok(emptyRecords),
            ("{\"id\":\"unprocessable_entity\",\"message\":\"name already exists\"}", 422),
            ok("{\"domain_record\":{}}")
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4"),
             DNSRecord(name: "vpn.example.com", type: .a, value: "203.0.113.5")],
            zone: "example.com")

        guard case .failed = outcomes[0].result else { return XCTFail("expected the first to fail") }
        XCTAssertEqual(outcomes[1].result, .created)
    }

    func testAMissingDomainIsReportedByName() async throws {
        let (provider, _) = provider([("{\"id\":\"not_found\",\"message\":\"domain not found\"}", 404)])
        do {
            _ = try await provider.publishReportingOutcomes(
                [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
                zone: "example.com")
            XCTFail("expected an error")
        } catch let error as DigitalOceanError {
            XCTAssertEqual(error, .zoneNotFound("example.com"))
        }
    }
}

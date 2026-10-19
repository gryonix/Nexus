import XCTest
@testable import gryonixNexusCore

final class GoDaddyDNSProviderTests: XCTestCase {
    private final class StubClient: GoDaddyHTTPClient, @unchecked Sendable {
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

    private func provider(_ responses: [(String, Int)]) -> (GoDaddyDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        return (GoDaddyDNSProvider(token: "test-token", http: client,
                                   baseURL: URL(string: "https://api.example.test/v3/domains")!),
                client)
    }

    private func ok(_ body: String) -> (String, Int) { (body, 200) }

    private let emptyItems = "{\"items\":[]}"

    // MARK: - Auth

    func testTheTokenGoesUpAsABearer() async throws {
        let (provider, client) = provider([ok(emptyItems), ok("{}")])
        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")
        XCTAssertEqual(client.sent.first?.authorization, "Bearer test-token")
    }

    func testVerifyTokenReadsTheDomainListAndWritesNothing() async throws {
        let (provider, client) = provider([ok("{\"items\":[]}")])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["GET"])
        XCTAssertEqual(client.sent.first?.url,
                       "https://api.example.test/v3/domains/domain-names?limit=1")
    }

    func testAnInvalidTokenIsReportedPlainly() async throws {
        let (provider, _) = provider([("{\"code\":\"INVALID_BODY\",\"message\":\"Authentication failed\"}", 401)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as GoDaddyError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedWithARelativeName() async throws {
        let (provider, client) = provider([ok(emptyItems), ok("{}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.url, "https://api.example.test/v3/domains/zones/example.com/dns-records")
        XCTAssertEqual(create.body?["type"] as? String, "A")
        XCTAssertEqual(create.body?["name"] as? String, "mail")
        XCTAssertEqual(create.body?["data"] as? String, "203.0.113.4")
        XCTAssertEqual(create.body?["ttl"] as? Int, 3600)
    }

    func testAnApexRecordIsNamedAt() async throws {
        let (provider, client) = provider([ok(emptyItems), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["name"] as? String, "@")
    }

    func testTheLookupFiltersByTypeAndName() async throws {
        let (provider, client) = provider([ok(emptyItems), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        let lookup = try XCTUnwrap(client.sent.first)
        XCTAssertEqual(lookup.method, "GET")
        XCTAssertEqual(lookup.url,
                       "https://api.example.test/v3/domains/zones/example.com/dns-records?name=mail&type=A")
    }

    func testAnMXTargetCarriesATrailingDot() async throws {
        let (provider, client) = provider([ok(emptyItems), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["data"] as? String, "mail.example.com.")
        XCTAssertEqual(client.sent.last?.body?["priority"] as? Int, 10)
    }

    func testASRVRecordFoldsWeightAndPortIntoData() async throws {
        let (provider, client) = provider([ok(emptyItems), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord.service(name: "_minecraft._tcp.example.com",
                               srv: .init(priority: 0, weight: 5, port: 25565,
                                         target: "mc.example.com"))],
            zone: "example.com")

        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.body?["data"] as? String, "5 25565 mc.example.com.")
        XCTAssertEqual(create.body?["priority"] as? Int, 0)
    }

    func testAChangedRecordIsUpdatedInPlaceKeepingTheExistingTTL() async throws {
        let existing = """
        {"items":[{"recordId":"rec_42","type":"A","name":"mail","data":"198.51.100.9","ttl":900}]}
        """
        let (provider, client) = provider([ok(existing), ok("{}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        let update = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(update.method, "PUT")
        XCTAssertEqual(update.url,
                       "https://api.example.test/v3/domains/zones/example.com/dns-records/rec_42")
        XCTAssertEqual(update.body?["ttl"] as? Int, 900)
    }

    func testAnIdenticalRecordIsLeftAlone() async throws {
        let existing = """
        {"items":[{"recordId":"rec_42","type":"A","name":"mail","data":"203.0.113.4","ttl":600}]}
        """
        let (provider, client) = provider([ok(existing)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 1, "nothing may be written when nothing changed")
    }

    func testALookupThatReturnsAMismatchedNameIsNotTrusted() async throws {
        let mismatched = """
        {"items":[{"recordId":"rec_1","type":"A","name":"other","data":"198.51.100.9"}]}
        """
        let (provider, client) = provider([ok(mismatched), ok("{}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        XCTAssertEqual(client.sent.last?.method, "POST")
    }

    func testOneRejectedRecordDoesNotAbandonTheRest() async throws {
        let (provider, _) = provider([
            ok(emptyItems),
            ("{\"code\":\"DUPLICATE_RECORD\",\"message\":\"a record already exists\"}", 422),
            ok(emptyItems),
            ok("{}"),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4"),
             DNSRecord(name: "vpn.example.com", type: .a, value: "203.0.113.5")],
            zone: "example.com")

        guard case .failed = outcomes[0].result else { return XCTFail("expected the first to fail") }
        XCTAssertEqual(outcomes[1].result, .created)
    }

    func testAMissingDomainIsReportedByName() async throws {
        let (provider, _) = provider([("{\"code\":\"NOT_FOUND\",\"message\":\"zone not found\"}", 404)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        guard case .failed(let message) = outcomes.first?.result else {
            return XCTFail("expected a per-record failure")
        }
        XCTAssertTrue(message.contains("example.com"), "the missing zone should be named: \(message)")
    }
}

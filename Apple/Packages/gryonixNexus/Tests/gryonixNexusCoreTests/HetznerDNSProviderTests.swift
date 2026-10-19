import XCTest
@testable import gryonixNexusCore

final class HetznerDNSProviderTests: XCTestCase {
    private final class StubClient: HetznerHTTPClient, @unchecked Sendable {
        struct Sent {
            let method: String
            let url: String
            let authToken: String?
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
                             authToken: request.value(forHTTPHeaderField: "Auth-API-Token"),
                             body: body))
            guard !responses.isEmpty else { return (Data("{}".utf8), 500) }
            return responses.removeFirst()
        }
    }

    private func provider(_ responses: [(String, Int)]) -> (HetznerDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        return (HetznerDNSProvider(token: "test-token", http: client,
                                   baseURL: URL(string: "https://api.example.test/v1")!),
                client)
    }

    private func ok(_ body: String) -> (String, Int) { (body, 200) }

    private let zoneLookup = "{\"zones\":[{\"id\":\"zone123\",\"name\":\"example.com\"}]}"
    private let emptyRecords = "{\"records\":[],\"meta\":{\"pagination\":{\"page\":1,\"last_page\":1}}}"

    // MARK: - Auth

    func testTheTokenGoesUpAsAuthAPIToken() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok(emptyRecords), ok("{}")])
        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")
        XCTAssertEqual(client.sent.first?.authToken, "test-token")
    }

    func testVerifyTokenReadsOneZoneAndWritesNothing() async throws {
        let (provider, client) = provider([ok("{\"zones\":[]}")])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["GET"])
    }

    func testAnInvalidTokenIsReportedPlainly() async throws {
        let (provider, _) = provider([("{\"error\":{\"message\":\"invalid auth\",\"code\":401}}", 401)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as HetznerError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedWithARelativeName() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok(emptyRecords), ok("{}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.url, "https://api.example.test/v1/records")
        XCTAssertEqual(create.body?["zone_id"] as? String, "zone123")
        XCTAssertEqual(create.body?["type"] as? String, "A")
        XCTAssertEqual(create.body?["name"] as? String, "mail")
        XCTAssertEqual(create.body?["value"] as? String, "203.0.113.4")
    }

    func testAnApexRecordIsNamedAt() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok(emptyRecords), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["name"] as? String, "@")
    }

    func testAnMXRecordFoldsThePriorityIntoTheValue() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok(emptyRecords), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["value"] as? String, "10 mail.example.com.")
    }

    func testAnSRVRecordFoldsAllFourFieldsIntoTheValue() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok(emptyRecords), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord.service(name: "_sip._tcp.example.com",
                               srv: .init(priority: 0, weight: 5, port: 5060, target: "sip.example.com"))],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["value"] as? String, "0 5 5060 sip.example.com.")
    }

    func testAChangedRecordIsUpdatedInPlace() async throws {
        let existing = """
        {"records":[{"id":"rec1","type":"A","name":"mail","value":"198.51.100.9"}],
         "meta":{"pagination":{"page":1,"last_page":1}}}
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        XCTAssertEqual(client.sent.last?.method, "PUT")
        XCTAssertEqual(client.sent.last?.url, "https://api.example.test/v1/records/rec1")
    }

    func testAnIdenticalRecordIsLeftAlone() async throws {
        let existing = """
        {"records":[{"id":"rec1","type":"A","name":"mail","value":"203.0.113.4"}],
         "meta":{"pagination":{"page":1,"last_page":1}}}
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 2, "nothing may be written when nothing changed")
    }

    func testPaginationFollowsLastPageNotAShortFinalBatch() async throws {
        let full = "{\"records\":[" + (1...100).map {
            "{\"id\":\"r\($0)\",\"type\":\"A\",\"name\":\"h\($0)\",\"value\":\"203.0.113.4\"}"
        }.joined(separator: ",") + "],\"meta\":{\"pagination\":{\"page\":1,\"last_page\":1}}}"
        let (provider, client) = provider([ok(zoneLookup), ok(full), ok("{}")])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "new.example.com", type: .a, value: "203.0.113.9")],
            zone: "example.com")

        XCTAssertEqual(client.sent.count, 3, "a last_page of 1 must not fetch a second page")
    }
}

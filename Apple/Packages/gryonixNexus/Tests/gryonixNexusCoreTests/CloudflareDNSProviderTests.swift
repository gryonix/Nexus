import XCTest
@testable import gryonixNexusCore

final class CloudflareDNSProviderTests: XCTestCase {
    // MARK: - Stub

    private final class StubClient: CloudflareHTTPClient, @unchecked Sendable {
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

    private func provider(_ responses: [(String, Int)]) -> (CloudflareDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        return (CloudflareDNSProvider(token: "test-token", http: client,
                                      baseURL: URL(string: "https://api.example.test/client/v4")!),
                client)
    }

    private func ok(_ result: String) -> (String, Int) {
        ("{\"success\":true,\"errors\":[],\"result\":\(result)}", 200)
    }

    private let zoneLookup = "[{\"id\":\"zone123\",\"name\":\"example.com\"}]"

    // MARK: - Writing

    func testAMissingRecordIsCreated() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok("[]"), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.url, "https://api.example.test/client/v4/zones/zone123/dns_records")
        XCTAssertEqual(create.body?["type"] as? String, "A")
        XCTAssertEqual(create.body?["name"] as? String, "mail.example.com")
        XCTAssertEqual(create.body?["content"] as? String, "203.0.113.4")
    }

    func testRecordsAreNeverProxied() async throws {
        let (provider, client) = provider([ok(zoneLookup), ok("[]"), ok("{}")])

        _ = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "vpn.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["proxied"] as? Bool, false)
    }

    func testAChangedRecordIsUpdatedInPlace() async throws {
        let existing = """
        [{"id":"rec1","type":"A","name":"mail.example.com","content":"198.51.100.9"}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        XCTAssertEqual(client.sent.last?.method, "PUT")
        XCTAssertEqual(client.sent.last?.url,
                       "https://api.example.test/client/v4/zones/zone123/dns_records/rec1")
    }

    /// Re-running must write nothing
    func testAnIdenticalRecordIsLeftAlone() async throws {
        let existing = """
        [{"id":"rec1","type":"A","name":"mail.example.com","content":"203.0.113.4"}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing)])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 2, "nothing may be written when nothing changed")
    }

    /// Cloudflare lower-cases names; the generator does not promise to
    func testMatchingIgnoresNameCase() async throws {
        let existing = """
        [{"id":"rec1","type":"A","name":"mail.example.com","content":"203.0.113.4"}]
        """
        let (provider, _) = provider([ok(zoneLookup), ok(existing)])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "MAIL.Example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
    }

    func testMXPriorityCountsAsAChange() async throws {
        let existing = """
        [{"id":"rec1","type":"MX","name":"example.com","content":"mail.example.com","priority":20}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        XCTAssertEqual(client.sent.last?.body?["priority"] as? Int, 10)
    }

    func testLongTXTValuesAreSentWhole() async throws {
        let key = "v=DKIM1; k=rsa; p=" + String(repeating: "A", count: 400)
        let (provider, client) = provider([ok(zoneLookup), ok("[]"), ok("{}")])

        _ = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "dkim._domainkey.example.com", type: .txt, value: key)],
            zone: "example.com")

        XCTAssertEqual(client.sent.last?.body?["content"] as? String, "\"\(key)\"")
    }

    func testRemovalTakesOnlyTheRecordsPointingAtTheServer() async throws {
        let existing = """
        [{"id":"a1","type":"A","name":"vault.example.com","content":"203.0.113.4"},
         {"id":"a2","type":"A","name":"vault.example.org","content":"198.51.100.9"},
         {"id":"a3","type":"TXT","name":"vault.example.com","content":"\\"keep\\""}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let removed = try await provider.removeAddressRecords(
            named: ["vault.example.com", "vault.example.org"], pointingAt: "203.0.113.4", zone: "example.com")

        XCTAssertEqual(removed, ["vault.example.com"], "a name pointed elsewhere stays")
        XCTAssertEqual(client.sent.last?.method, "DELETE")
        XCTAssertTrue(client.sent.last?.url.hasSuffix("dns_records/a1") ?? false)
    }

    func testAQuotedTXTRecordIsAlreadyCorrect() async throws {
        let existing = """
        [{"id":"rec1","type":"TXT","name":"example.com","content":"\\"v=spf1 mx \\" \\"-all\\""}]
        """
        let (provider, _) = provider([ok(zoneLookup), ok(existing)])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
    }

    func testAnUnquotedTXTRecordIsRewrittenQuoted() async throws {
        let existing = """
        [{"id":"rec1","type":"TXT","name":"example.com","content":"v=spf1 mx -all"}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        XCTAssertEqual(client.sent.last?.body?["content"] as? String, "\"v=spf1 mx -all\"")
    }

    func testSPFLeavesAnotherTXTAtTheSameNameAlone() async throws {
        let existing = """
        [{"id":"rec1","type":"TXT","name":"example.com","content":"\\"google-site-verification=abc\\""}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        XCTAssertEqual(client.sent.last?.method, "POST")
    }

    func testAnOldSPFIsUpdatedInPlace() async throws {
        let existing = """
        [{"id":"rec1","type":"TXT","name":"example.com","content":"\\"google-site-verification=abc\\""},
         {"id":"rec2","type":"TXT","name":"example.com","content":"\\"v=spf1 a -all\\""}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok(existing), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        XCTAssertEqual(client.sent.last?.method, "PUT")
        XCTAssertTrue(client.sent.last?.url.hasSuffix("/rec2") ?? false)
    }

    func testOneRejectedRecordDoesNotStopTheRest() async throws {
        let conflict = """
        {"success":false,"errors":[{"code":81053,"message":"An A record with that host already exists."}],"result":null}
        """
        let (provider, _) = provider([ok(zoneLookup), ok("[]"), (conflict, 400), ok("{}")])

        let outcomes = try await provider.applyReportingOutcomes([
            DNSRecord(name: "a.example.com", type: .a, value: "203.0.113.4"),
            DNSRecord(name: "b.example.com", type: .a, value: "203.0.113.5")
        ], zone: "example.com")

        XCTAssertEqual(outcomes.count, 2)
        guard case .failed(let message) = outcomes[0].result else {
            return XCTFail("the rejected record must report its reason")
        }
        XCTAssertTrue(message.contains("already exists"), message)
        XCTAssertEqual(outcomes[1].result, .created)
    }

    func testEveryPageOfExistingRecordsIsRead() async throws {
        let firstPage = (0..<100).map {
            "{\"id\":\"r\($0)\",\"type\":\"A\",\"name\":\"h\($0).example.com\",\"content\":\"203.0.113.1\"}"
        }.joined(separator: ",")
        let secondPage = """
        [{"id":"rec2","type":"A","name":"mail.example.com","content":"203.0.113.4"}]
        """
        let (provider, client) = provider([ok(zoneLookup), ok("[\(firstPage)]"), ok(secondPage)])

        let outcomes = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")],
            zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertTrue(client.sent[2].url.contains("page=2"), client.sent[2].url)
    }

    // MARK: - Zone and token

    func testZoneLookupUsesTheNameTheOwnerTyped() async throws {
        let (provider, client) = provider([ok(zoneLookup)])

        let id = try await provider.zoneID(for: "example.com")

        XCTAssertEqual(id, "zone123")
        XCTAssertEqual(client.sent.first?.url,
                       "https://api.example.test/client/v4/zones?name=example.com")
        XCTAssertEqual(client.sent.first?.authorization, "Bearer test-token")
    }

    func testAZoneThisAccountDoesNotHoldIsNamed() async throws {
        let (provider, _) = provider([ok("[]")])

        do {
            _ = try await provider.zoneID(for: "somebody-elses.com")
            XCTFail("a zone that is not in the account must not look like success")
        } catch let error as CloudflareError {
            XCTAssertEqual(error, .zoneNotFound("somebody-elses.com"))
        }
    }

    func testTheRealInvalidTokenResponseIsRecognised() async throws {
        let body = """
        {"success":false,"errors":[{"code":1000,"message":"Invalid API Token"}],"messages":[],"result":null}
        """
        let (provider, _) = provider([(body, 401)])

        do {
            try await provider.verifyToken()
            XCTFail("an invalid token must not verify")
        } catch let error as CloudflareError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    func testTheRealMalformedHeaderResponseIsRecognised() async throws {
        let body = """
        {"success":false,"errors":[{"code":6003,"message":"Invalid request headers","error_chain":[{"code":6111,"message":"Invalid format for Authorization header"}]}],"messages":[],"result":null}
        """
        let (provider, _) = provider([(body, 400)])

        do {
            try await provider.verifyToken()
            XCTFail("a malformed token must not verify")
        } catch let error as CloudflareError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    func testAFailureInsideATwoHundredIsStillAFailure() async throws {
        let body = """
        {"success":false,"errors":[{"code":7003,"message":"Could not route to /zones"}],"result":null}
        """
        let (provider, _) = provider([(body, 200)])

        do {
            try await provider.verifyToken()
            XCTFail("success:false must not be read as success")
        } catch let error as CloudflareError {
            XCTAssertEqual(error, .api(code: 7003, message: "Could not route to /zones"))
        }
    }
}

import XCTest
@testable import gryonixNexusCore

final class CloudflareTunnelProviderTests: XCTestCase {
    private final class StubClient: CloudflareHTTPClient, @unchecked Sendable {
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

    private let account = "acc123"

    private func provider(_ responses: [(String, Int)]) -> (CloudflareTunnelProvider, StubClient) {
        let client = StubClient(responses: responses)
        return (CloudflareTunnelProvider(token: "t", accountID: account, http: client,
                                         baseURL: URL(string: "https://api.example.test/client/v4")!),
                client)
    }

    private func ok(_ result: String) -> (String, Int) {
        ("{\"success\":true,\"errors\":[],\"result\":\(result)}", 200)
    }

    // MARK: - Finding and creating

    func testAnExistingTunnelIsReusedRatherThanDuplicated() async throws {
        let listing = "[{\"id\":\"tun-1\",\"name\":\"gryonixnexus-example-com\"}]"
        let (provider, client) = provider([ok(listing)])

        let id = try await provider.findOrCreateTunnel(named: "gryonixnexus-example-com")

        XCTAssertEqual(id, "tun-1")
        XCTAssertEqual(client.sent.count, 1, "nothing may be created when one already exists")
        XCTAssertEqual(client.sent[0].method, "GET")
        XCTAssertTrue(client.sent[0].url.contains("cfd_tunnel"), client.sent[0].url)
    }

    func testAMissingTunnelIsCreatedWithItsConfigurationHeldAtCloudflare() async throws {
        let (provider, client) = provider([ok("[]"), ok("{\"id\":\"tun-2\"}")])

        let id = try await provider.findOrCreateTunnel(named: "gryonixnexus-example-com")

        XCTAssertEqual(id, "tun-2")
        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.body?["name"] as? String, "gryonixnexus-example-com")
        XCTAssertEqual(create.body?["config_src"] as? String, "cloudflare")
    }

    func testATunnelWithAnotherNameIsNotAdopted() async throws {
        let listing = "[{\"id\":\"someone-elses\",\"name\":\"unrelated\"}]"
        let (provider, client) = provider([ok(listing), ok("{\"id\":\"tun-3\"}")])

        let id = try await provider.findOrCreateTunnel(named: "gryonixnexus-example-com")

        XCTAssertEqual(id, "tun-3")
        XCTAssertEqual(client.sent.last?.method, "POST")
    }

    // MARK: - Ingress

    func testEveryRouteEndsAtCaddyAndTheListEndsInACatchAll() async throws {
        let (provider, client) = provider([ok("{}")])

        try await provider.applyIngress(tunnelID: "tun-1", routes: [
            TunnelRoute(hostname: "vault.example.com"),
            TunnelRoute(hostname: "cloud.example.com"),
        ])

        let put = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(put.method, "PUT")
        let config = try XCTUnwrap(put.body?["config"] as? [String: Any])
        let ingress = try XCTUnwrap(config["ingress"] as? [[String: Any]])
        guard ingress.count == 3 else {
            return XCTFail("expected two names plus the catch-all, got \(ingress.count) rule(s)")
        }
        XCTAssertEqual(ingress[0]["hostname"] as? String, "vault.example.com")
        XCTAssertEqual(ingress[0]["service"] as? String, "https://127.0.0.1:443")
        let origin = try XCTUnwrap(ingress[0]["originRequest"] as? [String: Any])
        XCTAssertEqual(origin["noTLSVerify"] as? Bool, true)
        XCTAssertEqual(origin["originServerName"] as? String, "vault.example.com")
        XCTAssertNil(ingress[2]["hostname"])
        XCTAssertEqual(ingress[2]["service"] as? String, "http_status:404")
    }

    // MARK: - The names

    func testTunnelHostnamesAreProxiedUnlikeEveryOtherRecordThisAppWrites() async throws {
        let zone = "[{\"id\":\"zone-1\",\"name\":\"example.com\"}]"
        let (provider, client) = provider([ok(zone), ok("[]"), ok("{}")])

        _ = try await provider.publishHostnames(["vault.example.com"],
                                                tunnelID: "tun-1", zone: "example.com")

        let create = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.body?["type"] as? String, "CNAME")
        XCTAssertEqual(create.body?["content"] as? String, "tun-1.cfargotunnel.com")
        XCTAssertEqual(create.body?["proxied"] as? Bool, true)
    }

    /// Republishing must update in place
    func testAnExistingHostnameIsUpdatedRatherThanAddedTwice() async throws {
        let zone = "[{\"id\":\"zone-1\",\"name\":\"example.com\"}]"
        let existing = """
        [{"id":"rec-1","type":"CNAME","name":"vault.example.com","content":"old.cfargotunnel.com"}]
        """
        let (provider, client) = provider([ok(zone), ok(existing), ok("{}")])

        _ = try await provider.publishHostnames(["vault.example.com"],
                                                tunnelID: "tun-9", zone: "example.com")

        let update = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(update.method, "PUT")
        XCTAssertTrue(update.url.hasSuffix("/dns_records/rec-1"), update.url)
        XCTAssertEqual(update.body?["content"] as? String, "tun-9.cfargotunnel.com")
    }

    /// Address records for the name would block the CNAME
    func testAddressRecordsForTheNameMakeWayForTheTunnel() async throws {
        let zone = "[{\"id\":\"zone-1\",\"name\":\"example.com\"}]"
        let existing = """
        [{"id":"rec-a","type":"A","name":"vault.example.com","content":"203.0.113.9"},
         {"id":"rec-mx","type":"MX","name":"vault.example.com","content":"mail.example.com"}]
        """
        let (provider, client) = provider([ok(zone), ok(existing), ok("{}"), ok("{}")])

        _ = try await provider.publishHostnames(["vault.example.com"],
                                                tunnelID: "tun-1", zone: "example.com")

        XCTAssertTrue(client.sent[1].url.contains("name=vault.example.com"), client.sent[1].url)
        XCTAssertEqual(client.sent[2].method, "DELETE")
        XCTAssertTrue(client.sent[2].url.hasSuffix("/dns_records/rec-a"), client.sent[2].url)
        XCTAssertEqual(client.sent[3].method, "POST")
        XCTAssertEqual(client.sent.count, 4, "the MX record stays")
    }

    // MARK: - Discovery and refusals

    func testTheAccountIdIsReadOffAZone() async throws {
        let zones = """
        [{"id":"zone-1","name":"example.com","account":{"id":"acc-42","name":"Owner"}}]
        """
        let client = StubClient(responses: [(("{\"success\":true,\"errors\":[],\"result\":\(zones)}"), 200)])

        let id = try await CloudflareTunnelProvider.accountID(
            token: "t", http: client, baseURL: URL(string: "https://api.example.test/client/v4")!)

        XCTAssertEqual(id, "acc-42")
    }

    func testAnAccountLevelRefusalCarriesCloudflaresOwnWords() async throws {
        let denied = """
        {"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"result":null}
        """
        let (provider, _) = provider([(denied, 403)])

        do {
            _ = try await provider.findOrCreateTunnel(named: "x")
            XCTFail("a refusal must not look like a tunnel")
        } catch let error as CloudflareError {
            XCTAssertEqual(error, .invalidToken)
        }
    }
}

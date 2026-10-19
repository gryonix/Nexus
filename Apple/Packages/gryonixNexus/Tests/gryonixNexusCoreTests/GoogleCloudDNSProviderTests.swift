import Security
import XCTest
@testable import gryonixNexusCore

final class GoogleCloudDNSProviderTests: XCTestCase {
    private final class StubClient: GoogleCloudDNSHTTPClient, @unchecked Sendable {
        struct Sent {
            let method: String
            let url: String
            let headers: [String: String]
            let rawBody: String?
            let jsonBody: [String: Any]?
        }

        private let lock = NSLock()
        private var responses: [(Data, Int)]
        private(set) var sent: [Sent] = []

        init(responses: [(String, Int)]) {
            self.responses = responses.map { (Data($0.0.utf8), $0.1) }
        }

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            lock.lock(); defer { lock.unlock() }
            let raw = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
            let json = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            sent.append(Sent(method: request.httpMethod ?? "",
                             url: request.url?.absoluteString ?? "",
                             headers: request.allHTTPHeaderFields ?? [:],
                             rawBody: raw, jsonBody: json))
            guard !responses.isEmpty else { return (Data("{}".utf8), 500) }
            return responses.removeFirst()
        }
    }

    private static let testPrivateKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQD5wt9k/BD9isVC
    PkrLrU3WU5rIeg1Wb+U3avXMfW63ejED5nZh18hq0LI1SVI9Dzyzg0tu9CTdB/p5
    2847SxrDLrixmJd9vG+sz7MMzu5Se4auGy9Wv8jHlMbuIAeDUzeJtSZsMcW0YZlY
    /vBI2p4w8x1o4vBghhXB3o3egLQ/+mTLHRdHAWVVSZl/TLGuYVyFEOzmtV4VLkcs
    ILojy094Oy5/4zbv9HsuLYGKsjxUT/iq0TVbozfmWnMRUjAHDGGb0jFF7HEEczI8
    GXG3tsIbE0pliiQ/yFlrUOUls1e7ey9KShndVwGhcdA7S7IMSO+g7QLGAqkKWXZq
    nz9aDLYLAgMBAAECggEADKWs8QzAKEz60iQcK3yNTXlF6p+4Xy3vwHYLflBeGkjD
    6whxHcemEwQzkfX/H3wCPRQJiAb+FHpov5Twa3/RGhy0JrutKCVlNK3+/HraBi+e
    t60R7f85W1argB4usAK3WqMwQxhK6s7Qy6xIXjGonJ5WJejsw4zmoYuNSYmtsI0t
    Ke6OCgzL4xfUa8iVm7NwWX6p9hvKmRV/ojAUx2exbGxxWvJe6i5P42T/lAb3GQM6
    rrgLuVww2YbUUy1jAHMnefKpZg3K2Fweccf9G1Dq3wG4goR/jK0CO9E8NBSLFKYj
    /qLTomc/mckibDjt8C7BJADXqtB//1put6PXHA+UmQKBgQD+Gv4xWtIG7KAOxoXz
    s84kuL1lISJTyS9FIYG9WP2i375Gdw1AKYuyy/5NBYaQRyUPEUBT6K11n70kJgD5
    igPk/DuqKPJgxQObEh/IWC/SEYzQZvp5SZVPA+/+AEeaP8x6QMoQujX7MTvCNQn3
    gNrxeQUDBzLur73TjnRy3BFJbwKBgQD7n5aD4EWPM4izrr9iLKqyHjPh/3rjCq5f
    BUI0c1HsJpt4pM4bNGkGNiVJdEvoSOlGDLJXUetcCiE/BxRRwzwdgC5UdBm62z98
    LB4A73xW5x79m/1nQ8p9oo5Gj4ZPfwNnku7N/6c4IUExe1RedeZyVVvn08fnqZUi
    rVCl5f33JQKBgBFvpruaQMkq2XzKEIz9bIrGhnB3CpT3PCAhQXbNsXHIqpTJPIaH
    k0dsigGc/HPP/fH/vAtF7wkgMelWFkEJQGUpDasKbj9HpYyxfK7Rpk5i1+fA+TTz
    YKRwX7ptKHykHhLReUwWive2lCQqYYmzNNLW/AoOJ2eLdZobr0/mW+VPAoGAJQb6
    8zURh10iBK72YtAH3mYrZFpgDwEHX9w6PdWqfIHB5yL5YW949P0Kx6BhezEfgrtj
    kw3vAIBNHCVCjDWapwyxxKPBFYol8XPchm63cWJZYSCPTZ7gMVS2cxOzxAcAzUEF
    +zJfvRbHrSxk4fGfk7uT5q13gVOnKo8uivspQDECgYEAj/KenYslPL6il+L6k4I1
    X39lcfdKHMISDD2Qo868EVVDchxN1lH1/RlZ0huYJ4OAORyneqobURgslj39T1Iy
    kKtUULELJWaqnjVCTM166T9OkRSF3KgZdw8PrEcYcFXMPWijW2wd087AIBCzAR/k
    qlSZtoi6KDhhBpWb68hJNuE=
    -----END PRIVATE KEY-----
    """

    private func serviceAccountJSON(privateKey: String? = testPrivateKeyPEM,
                                    clientEmail: String? = "svc@test-project.iam.gserviceaccount.com",
                                    projectID: String? = "test-project",
                                    tokenURI: String? = nil) -> String {
        var dict: [String: Any] = [:]
        if let privateKey { dict["private_key"] = privateKey }
        if let clientEmail { dict["client_email"] = clientEmail }
        if let projectID { dict["project_id"] = projectID }
        if let tokenURI { dict["token_uri"] = tokenURI }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(decoding: data, as: UTF8.self)
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func provider(_ responses: [(String, Int)], token: String? = nil)
        -> (GoogleCloudDNSProvider, StubClient) {
        let client = StubClient(responses: responses)
        let provider = GoogleCloudDNSProvider(
            token: token ?? serviceAccountJSON(), http: client,
            baseURL: URL(string: "https://dns.example.test/dns/v1")!,
            clock: { Self.fixedNow })
        return (provider, client)
    }

    private func ok(_ body: String) -> (String, Int) { (body, 200) }

    private func tokenOK(_ accessToken: String = "test-access-token") -> (String, Int) {
        ok(#"{"access_token":"\#(accessToken)","expires_in":3599,"token_type":"Bearer"}"#)
    }

    private func zoneList(name: String = "example-com", dnsName: String = "example.com.") -> String {
        #"{"managedZones":[{"name":"\#(name)","dnsName":"\#(dnsName)"}]}"#
    }

    private let emptyRRSets = #"{"rrsets":[]}"#

    private func rrset(type: String, ttl: Int, values: [String]) -> String {
        let quoted = values.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"rrsets":[{"type":"\#(type)","ttl":\#(ttl),"rrdatas":[\#(quoted)]}]}"#
    }

    private let changesOK = #"{"id":"1","status":"pending"}"#

    // MARK: - Auth / credentials

    func testAMalformedTokenIsRefusedBeforeAnyRequest() async throws {
        let (provider, client) = provider([], token: "not json")
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as GoogleCloudDNSError {
            XCTAssertEqual(error, .malformedToken)
        }
        XCTAssertTrue(client.sent.isEmpty, "a malformed token must not reach the network")
    }

    func testAMissingFieldIsRefused() async throws {
        let (provider, client) = provider([], token: serviceAccountJSON(projectID: nil))
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as GoogleCloudDNSError {
            XCTAssertEqual(error, .malformedToken)
        }
        XCTAssertTrue(client.sent.isEmpty)
    }

    func testVerifyTokenExchangesAJWTThenListsZonesAndWritesNothing() async throws {
        let (provider, client) = provider([tokenOK(), ok(#"{"managedZones":[]}"#)])
        try await provider.verifyToken()
        XCTAssertEqual(client.sent.map(\.method), ["POST", "GET"])
        XCTAssertEqual(client.sent[0].url, "https://oauth2.googleapis.com/token")
        XCTAssertTrue(client.sent[1].url.hasPrefix("https://dns.example.test/dns/v1/projects/test-project/managedZones"))
        XCTAssertEqual(client.sent[1].headers["Authorization"], "Bearer test-access-token")
    }

    func testTheTokenExchangeCarriesTheJWTBearerGrant() async throws {
        let (provider, client) = provider([tokenOK(), ok(#"{"managedZones":[]}"#)])
        try await provider.verifyToken()
        let body = try XCTUnwrap(client.sent.first?.rawBody)
        XCTAssertTrue(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"))
        XCTAssertTrue(body.contains("assertion="))
    }

    func testTheJWTSignatureVerifiesAgainstTheKeysOwnPublicHalf() async throws {
        let (provider, client) = provider([tokenOK(), ok(#"{"managedZones":[]}"#)])
        try await provider.verifyToken()
        let body = try XCTUnwrap(client.sent.first?.rawBody)
        let assertion = try XCTUnwrap(
            body.components(separatedBy: "&").first { $0.hasPrefix("assertion=") }?
                .dropFirst("assertion=".count).removingPercentEncoding)
        let parts = assertion.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3, "header.payload.signature")

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let signature = try XCTUnwrap(Self.base64URLDecode(parts[2]))

        let privateKey = try XCTUnwrap(Self.rsaPrivateKey(fromPEM: Self.testPrivateKeyPEM))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        var error: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                             signingInput as CFData, signature as CFData, &error)
        XCTAssertTrue(verified, "signature did not verify: \(String(describing: error?.takeRetainedValue()))")

        // And the claims themselves — issuer, scope, audience, lifetime.
        let payloadData = try XCTUnwrap(Self.base64URLDecode(parts[1]))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(payload["iss"] as? String, "svc@test-project.iam.gserviceaccount.com")
        XCTAssertEqual(payload["scope"] as? String, "https://www.googleapis.com/auth/ndev.clouddns.readwrite")
        XCTAssertEqual(payload["aud"] as? String, "https://oauth2.googleapis.com/token")
        let iat = try XCTUnwrap(payload["iat"] as? Int)
        let exp = try XCTUnwrap(payload["exp"] as? Int)
        XCTAssertEqual(exp - iat, 3600)
    }

    func testAnUnauthorizedTokenExchangeIsReportedAsInvalid() async throws {
        let (provider, _) = provider([("{\"error\":\"invalid_grant\"}", 401)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as GoogleCloudDNSError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    func testAForbiddenZonesCallIsReportedAsInvalid() async throws {
        let (provider, _) = provider([tokenOK(), ("{\"error\":{\"message\":\"forbidden\"}}", 403)])
        do {
            try await provider.verifyToken()
            XCTFail("expected an error")
        } catch let error as GoogleCloudDNSError {
            XCTAssertEqual(error, .invalidToken)
        }
    }

    // MARK: - Zone lookup

    func testAMissingZoneIsNamedInTheError() async throws {
        let (provider, _) = provider([tokenOK(), ok(#"{"managedZones":[]}"#)])
        do {
            _ = try await provider.publishReportingOutcomes(
                [DNSRecord(name: "mail.nope.com", type: .a, value: "203.0.113.4")], zone: "nope.com")
            XCTFail("expected an error")
        } catch let error as GoogleCloudDNSError {
            XCTAssertEqual(error, .zoneNotFound("nope.com"))
        }
    }

    func testAZoneNameThatDoesNotMatchIsNotTrusted() async throws {
        let (provider, _) = provider([tokenOK(), ok(zoneList(dnsName: "example.org."))])
        do {
            _ = try await provider.publishReportingOutcomes(
                [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")
            XCTFail("expected an error")
        } catch let error as GoogleCloudDNSError {
            XCTAssertEqual(error, .zoneNotFound("example.com"))
        }
    }

    func testZoneLookupFollowsNextPageToken() async throws {
        let (provider, client) = provider([
            tokenOK(),
            ok(#"{"managedZones":[{"name":"other-zone","dnsName":"other.com."}],"nextPageToken":"p2"}"#),
            ok(zoneList()),
            ok(emptyRRSets),
            ok(changesOK),
        ])
        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")
        XCTAssertEqual(outcomes.map(\.result), [.created])
        XCTAssertTrue(client.sent[2].url.contains("pageToken=p2"))
    }

    // MARK: - Writing

    func testAMissingRecordIsCreatedWithOneValue() async throws {
        let (provider, client) = provider([tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.created])
        let change = try XCTUnwrap(client.sent.last)
        XCTAssertEqual(change.method, "POST")
        XCTAssertTrue(change.url.hasSuffix("/changes"))
        let additions = try XCTUnwrap(change.jsonBody?["additions"] as? [[String: Any]])
        XCTAssertEqual(additions.first?["name"] as? String, "mail.example.com.")
        XCTAssertEqual(additions.first?["rrdatas"] as? [String], ["203.0.113.4"])
        XCTAssertNil(change.jsonBody?["deletions"], "nothing existed yet — no deletions expected")
    }

    func testAnExistingSingleValueMatchIsUnchangedAndNothingIsWritten() async throws {
        let (provider, client) = provider([
            tokenOK(), ok(zoneList()), ok(rrset(type: "A", ttl: 300, values: ["203.0.113.4"])),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 3, "unchanged must not call changes.create")
    }

    func testAnExistingMultiValueSetKeepsItsOtherValuesOnUpdate() async throws {
        let (provider, client) = provider([
            tokenOK(), ok(zoneList()),
            ok(rrset(type: "A", ttl: 300, values: ["198.51.100.1", "198.51.100.2"])),
            ok(changesOK),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "198.51.100.3")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.updated])
        let change = try XCTUnwrap(client.sent.last)
        let additions = try XCTUnwrap(change.jsonBody?["additions"] as? [[String: Any]])
        let deletions = try XCTUnwrap(change.jsonBody?["deletions"] as? [[String: Any]])
        let addedValues = try XCTUnwrap(additions.first?["rrdatas"] as? [String])
        for value in ["198.51.100.1", "198.51.100.2", "198.51.100.3"] {
            XCTAssertTrue(addedValues.contains(value), "missing \(value) in \(addedValues)")
        }
        XCTAssertEqual(deletions.first?["rrdatas"] as? [String], ["198.51.100.1", "198.51.100.2"])
    }

    func testAValueAlreadyInAMultiValueSetIsUnchanged() async throws {
        let (provider, client) = provider([
            tokenOK(), ok(zoneList()),
            ok(rrset(type: "A", ttl: 300, values: ["198.51.100.1", "198.51.100.2"])),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .a, value: "198.51.100.2")], zone: "example.com")

        XCTAssertEqual(outcomes.map(\.result), [.unchanged])
        XCTAssertEqual(client.sent.count, 3)
    }

    func testAnMXRecordFoldsThePriorityIntoTheValue() async throws {
        let (provider, client) = provider([tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .mx, value: "mail.example.com", priority: 10)],
            zone: "example.com")

        let additions = try XCTUnwrap(client.sent.last?.jsonBody?["additions"] as? [[String: Any]])
        XCTAssertEqual(additions.first?["rrdatas"] as? [String], ["10 mail.example.com."])
    }

    func testASRVRecordFoldsAllFourFieldsIntoTheValue() async throws {
        let (provider, client) = provider([tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord.service(name: "_minecraft._tcp.example.com",
                               srv: .init(priority: 0, weight: 5, port: 25565, target: "mc.example.com"))],
            zone: "example.com")

        let additions = try XCTUnwrap(client.sent.last?.jsonBody?["additions"] as? [[String: Any]])
        XCTAssertEqual(additions.first?["rrdatas"] as? [String], ["0 5 25565 mc.example.com."])
    }

    func testATXTRecordIsSentQuoted() async throws {
        let (provider, client) = provider([tokenOK(), ok(zoneList()), ok(emptyRRSets), ok(changesOK)])

        _ = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "example.com", type: .txt, value: "v=spf1 -all")], zone: "example.com")

        let additions = try XCTUnwrap(client.sent.last?.jsonBody?["additions"] as? [[String: Any]])
        XCTAssertEqual(additions.first?["rrdatas"] as? [String], ["\"v=spf1 -all\""])
    }

    func testOneFailedRecordDoesNotAbandonTheRest() async throws {
        let (provider, _) = provider([
            tokenOK(), ok(zoneList()),
            ("{\"error\":{\"message\":\"quota exceeded\"}}", 429),
            ok(emptyRRSets), ok(changesOK),
        ])

        let outcomes = try await provider.publishReportingOutcomes(
            [DNSRecord(name: "a.example.com", type: .a, value: "203.0.113.4"),
             DNSRecord(name: "b.example.com", type: .a, value: "203.0.113.5")],
            zone: "example.com")

        XCTAssertEqual(outcomes.count, 2)
        guard case .failed = outcomes[0].result else { return XCTFail("expected the first record to fail") }
        XCTAssertEqual(outcomes[1].result, .created)
    }

    private static func rsaPrivateKey(fromPEM pem: String) -> SecKey? {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: stripped),
              let pkcs1 = DERReader.pkcs1FromPKCS8(der) else { return nil }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}

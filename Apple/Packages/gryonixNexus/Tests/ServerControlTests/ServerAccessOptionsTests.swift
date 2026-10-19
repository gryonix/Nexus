import XCTest

@testable import ServerControl

final class ServerAccessOptionsTests: XCTestCase {
    private func roundTrip(_ options: ServerAccessOptions) throws -> ServerAccessOptions {
        let data = try JSONEncoder().encode(options)
        return try JSONDecoder().decode(ServerAccessOptions.self, from: data)
    }

    func testEverythingSurvivesARoundTrip() throws {
        let options = ServerAccessOptions(
            agentForwarding: true,
            sftpDirectory: "/srv",
            bastion: .manual(HostEndpoint(host: "jump.example", port: 2222, user: "ops")),
            fallback: FallbackAddress(host: "203.0.113.9", port: 22,
                                      bastion: .fleetServer(UUID())))
        XCTAssertEqual(try roundTrip(options), options)
    }

    func testAnOlderRecordDecodesAsNothingChosen() throws {
        let data = Data("{}".utf8)
        let options = try JSONDecoder().decode(ServerAccessOptions.self, from: data)
        XCTAssertEqual(options, .none)
        XCTAssertTrue(options.isEmpty)
    }

    func testAnEmptyHostFallsBackToThePrimaryAddress() {
        let primary = HostEndpoint(host: "203.0.113.4", port: 22, user: "root")
        let fallback = FallbackAddress(bastion: .fleetServer(UUID()))
        XCTAssertEqual(fallback.endpoint(primary: primary), primary)
    }

    func testATypedAddressReplacesTheHostButKeepsTheAccount() {
        let primary = HostEndpoint(host: "203.0.113.4", port: 22, user: "root")
        let fallback = FallbackAddress(host: " 198.51.100.7 ")
        let resolved = fallback.endpoint(primary: primary)
        XCTAssertEqual(resolved.host, "198.51.100.7", "the typed address was not trimmed")
        XCTAssertEqual(resolved.port, 22)
        XCTAssertEqual(resolved.user, "root", "the account is the deployment's, never re-typed")
    }

    func testAFallbackThatChangesNothingIsNotUsable() {
        XCTAssertFalse(FallbackAddress().isUsable)
        XCTAssertFalse(FallbackAddress(host: "   ").isUsable)
        XCTAssertTrue(FallbackAddress(host: "198.51.100.7").isUsable)
        XCTAssertTrue(FallbackAddress(bastion: .fleetServer(UUID())).isUsable)
    }

    func testAHopThatNamesNothingIsNotAHop() {
        XCTAssertFalse(BastionHop().isUsable)
        XCTAssertTrue(BastionHop.fleetServer(UUID()).isUsable)
        XCTAssertFalse(BastionHop.manual(HostEndpoint(host: "", port: 22, user: "ops")).isUsable)
    }

    func testAHopIsStoredAsTwoPlainFields() throws {
        let data = try JSONEncoder().encode(BastionHop.manual(
            HostEndpoint(host: "jump.example", port: 22, user: "ops")))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["manual"], "the manual endpoint is not a plain field any more")
        XCTAssertNil(object["_0"], "the hop encodes as an enum again — Kotlin cannot read that")
    }

    func testAHopAnswersOnlyForItsOwnKind() {
        let id = UUID()
        XCTAssertEqual(BastionHop.fleetServer(id).fleetServerID, id)
        XCTAssertNil(BastionHop.fleetServer(id).manual)
        let endpoint = HostEndpoint(host: "jump.example", port: 22, user: "ops")
        XCTAssertEqual(BastionHop.manual(endpoint).manual, endpoint)
        XCTAssertNil(BastionHop.manual(endpoint).fleetServerID)
    }
}

import XCTest
@testable import gryonixNexusCore

/// TEMPORARY — not to be committed
final class TempLiveCloudflareTests: XCTestCase {
    private var token: String {
        ProcessInfo.processInfo.environment["CF_TOKEN"] ?? ""
    }

    func testLiveCreateThenUpdateThenUnchanged() async throws {
        try XCTSkipIf(token.isEmpty, "no CF_TOKEN")
        let provider = CloudflareDNSProvider(token: token)
        let name = "gryonixnexus-verify.gryonix.com"

        // 1. create
        let first = try await provider.applyReportingOutcomes(
            [DNSRecord(name: name, type: .txt, value: "one", comment: "gryonixNexus live check")],
            zone: "gryonix.com")
        print("LIVE-1 \(first.map(\.result))")

        // 2. same value again — must write nothing
        let second = try await provider.applyReportingOutcomes(
            [DNSRecord(name: name, type: .txt, value: "one")], zone: "gryonix.com")
        print("LIVE-2 \(second.map(\.result))")

        // 3. changed value — must update in place, not duplicate
        let third = try await provider.applyReportingOutcomes(
            [DNSRecord(name: name, type: .txt, value: "two")], zone: "gryonix.com")
        print("LIVE-3 \(third.map(\.result))")

        let key = "v=DKIM1; k=rsa; p=" + String(repeating: "A", count: 400)
        let fourth = try await provider.applyReportingOutcomes(
            [DNSRecord(name: "gryonixnexus-verify-dkim.gryonix.com", type: .txt, value: key)],
            zone: "gryonix.com")
        print("LIVE-4 \(fourth.map(\.result))")

        XCTAssertEqual(first.map(\.result), [.created])
        XCTAssertEqual(second.map(\.result), [.unchanged])
        XCTAssertEqual(third.map(\.result), [.updated])
        XCTAssertEqual(fourth.map(\.result), [.created])
    }
}

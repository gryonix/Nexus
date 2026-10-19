import XCTest
@testable import ServerControl

private actor RecordingLockdown: AdminLockdownManaging {
    private(set) var calls: [String] = []

    func status() async throws -> AdminLockdownState { .off }

    func set(_ enabled: Bool) async throws -> AdminLockdownState {
        calls.append(enabled ? "on" : "off")
        return enabled ? .all : .off
    }

    func set(hosts: [String]) async throws -> AdminLockdownState {
        calls.append("only " + hosts.joined(separator: " "))
        return .only(Set(hosts))
    }
}

final class AdminLockdownRestoreTests: XCTestCase {
    func testEachStateIsPutBackTheWayItWasRead() async throws {
        let lockdown = RecordingLockdown()
        try await lockdown.restore(.all)
        try await lockdown.restore(.only(["b.example.net", "a.example.net"]))
        try await lockdown.restore(.off)
        let calls = await lockdown.calls
        XCTAssertEqual(calls, ["on", "only a.example.net b.example.net", "off"])
    }
}

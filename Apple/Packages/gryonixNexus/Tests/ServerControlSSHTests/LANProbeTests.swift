import Foundation
import Network
import XCTest

@testable import ServerControlSSH

/// The local network is tried only when it answers
final class LANProbeTests: XCTestCase {
    private func listen(greeting: Data?) async throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            if let greeting { connection.send(content: greeting, completion: .idempotent) }
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        return listener
    }

    func testAnSSHServerAnswers() async throws {
        let listener = try await listen(greeting: Data("SSH-2.0-OpenSSH_9.2\r\n".utf8))
        defer { listener.cancel() }
        let answered = await LANProbe.answers(host: "127.0.0.1", port: Int(listener.port?.rawValue ?? 0))
        XCTAssertTrue(answered)
    }

    func testASilentAcceptIsNotTheMachine() async throws {
        let listener = try await listen(greeting: nil)
        defer { listener.cancel() }
        let answered = await LANProbe.answers(host: "127.0.0.1", port: Int(listener.port?.rawValue ?? 0),
                                              within: .milliseconds(600))
        XCTAssertFalse(answered, "a VPN that accepts locally must not count as the LAN")
    }

    func testOnlyAnSSHGreetingCounts() {
        XCTAssertTrue(LANProbe.isSSHBanner(Data("SSH-2.0-x".utf8)))
        XCTAssertFalse(LANProbe.isSSHBanner(Data("HTTP/1.1".utf8)))
        XCTAssertFalse(LANProbe.isSSHBanner(Data()))
    }

    func testAnAddressThatNeverAnswersGivesUpInTime() async {
        let started = Date()
        let answered = await LANProbe.answers(host: "192.0.2.1", port: 22, within: .milliseconds(400))
        XCTAssertFalse(answered)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}

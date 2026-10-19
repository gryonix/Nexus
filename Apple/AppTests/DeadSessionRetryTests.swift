import AgentClient
import ServerControl
import XCTest

@testable import gryonixNexus

/// A session the server closed while the phone slept
@MainActor
final class DeadSessionRetryTests: XCTestCase {
    private func model() -> DashboardViewModel {
        var deployment = Deployment(name: "adopted",
                                    topology: .singleHost,
                                    domain: "example.com",
                                    entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                                    services: [.vaultwarden])
        deployment.usesAgent = true
        return DashboardViewModel(deployment: deployment,
                                  makeRunner: { DemoCommandRunner(deployment: $0) })
    }

    func testAClosedChannelIsTriedAgainOnAFreshSession() async throws {
        let model = model()
        var attempts = 0
        let answer = try await model.onLiveSession { () -> Int in
            attempts += 1
            if attempts == 1 { throw AgentError.transport("channel closed by the server") }
            return 42
        }
        XCTAssertEqual(answer, 42)
        XCTAssertEqual(attempts, 2, "a dead session has to be rebuilt and the work run again")
    }

    /// Twice and no more
    func testItGivesUpAfterTheSecondTry() async {
        let model = model()
        var attempts = 0
        do {
            _ = try await model.onLiveSession { () -> Int in
                attempts += 1
                throw AgentError.transport("connection reset by peer")
            }
            XCTFail("an unreachable host must report itself")
        } catch {
            XCTAssertEqual(attempts, 2, "the work ran \(attempts) times")
        }
    }

    /// A refusal must not be repeated as a retry
    func testAnAnsweredCallIsNotRetried() async {
        let model = model()
        var attempts = 0
        do {
            _ = try await model.onLiveSession { () -> Int in
                attempts += 1
                throw AgentError.rpc(code: "invalid_argument", message: "unknown service 'x'")
            }
            XCTFail("a refusal must reach the caller")
        } catch {
            XCTAssertEqual(attempts, 1, "a refusal was retried")
        }
    }

    func testWhatCountsAsADeadSession() {
        XCTAssertTrue(DashboardViewModel.isDeadSession(AgentError.transport("bad status line")))
        XCTAssertTrue(DashboardViewModel.isDeadSession(
            ServerControlError.commandFailed(command: "ls", exitCode: nil,
                                             stderr: "the channel was closed")))
        XCTAssertFalse(DashboardViewModel.isDeadSession(
            AgentError.rpc(code: "failed_precondition", message: "no key")))
        XCTAssertFalse(DashboardViewModel.isDeadSession(ServerControlError.sudoPasswordRequired(command: "docker ps")))
    }
}

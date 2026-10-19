import Foundation
@testable import ServerControl
import XCTest

final class DetachedAgentBuildTests: XCTestCase {
    func testTheReaderCountsLinesAcrossCutChunksAndFindsTheExitCode() {
        var reader = BuildLogReader()
        XCTAssertEqual(reader.feed("Compiling ser"), [])
        XCTAssertEqual(reader.feed("de\r\n\nFinished\n"), ["Compiling serde", "Finished"])
        XCTAssertEqual(reader.linesSeen, 3)
        XCTAssertNil(reader.exitCode)
        XCTAssertEqual(reader.feed("\(DetachedAgentBuild.exitMarker)0\n"), [])
        XCTAssertEqual(reader.exitCode, 0)
        XCTAssertEqual(reader.transcript, "Compiling serde\nFinished\n")
    }

    func testTheBuildRunsInItsOwnSessionAndLogsBesideTheHome() {
        let build = DetachedAgentBuild(home: "/home/it's")
        let start = build.startCommand(fetchScript: nil, wrapper: "/opt/wrapper.sh")
        XCTAssertTrue(start.hasPrefix("bash -c "))
        XCTAssertTrue(start.contains("setsid nohup bash -c"))
        XCTAssertTrue(start.contains("sudo -n /opt/wrapper.sh"))
        XCTAssertTrue(start.contains(".gryonixnexus-agent-build.log"))
        XCTAssertFalse(start.contains("R=$?"))
        let fetched = build.startCommand(fetchScript: "/home/x/fetch.sh", wrapper: "/opt/wrapper.sh")
        XCTAssertTrue(fetched.contains("R=$?"))
        XCTAssertTrue(build.followCommand(fromLine: 42).contains("tail -n +42"))
    }

    func testADroppedLinkIsReopenedFromTheFirstUnreadLine() async throws {
        let runner = ScriptedRunner(streams: [
            .init(lines: "one\ntwo\nthr", fails: true),
            .init(lines: "three\n\(DetachedAgentBuild.exitMarker)0\n", fails: false),
        ])
        let build = DetachedAgentBuild(home: "/root", retryDelay: .milliseconds(1))
        let reconnects = Counter()
        let backs = Counter()
        let outcome = try await build.follow(runner: runner, host: .vps, onOutput: { _ in },
                                             onReconnect: { _ in reconnects.bump() },
                                             onReconnected: { backs.bump() })
        XCTAssertEqual(outcome, .init(exitCode: 0, transcript: "one\ntwo\nthree\n"))
        XCTAssertEqual(reconnects.value, 1)
        XCTAssertEqual(backs.value, 1, "the link coming back is reported once")
        let commands = await runner.streamed
        XCTAssertTrue(commands[0].contains("tail -n +1 "))
        XCTAssertTrue(commands[1].contains("tail -n +3 "), "the cut line is read again")
    }

    func testABuildThatDiesWithoutTheMarkerIsAFailure() async throws {
        let runner = ScriptedRunner(streams: [.init(lines: "killed\n", fails: false)])
        let build = DetachedAgentBuild(home: "/root", retryDelay: .milliseconds(1))
        let outcome = try await build.follow(runner: runner, host: .vps, onOutput: { _ in }, onReconnect: { _ in })
        XCTAssertEqual(outcome.exitCode, -1)
        XCTAssertEqual(outcome.transcript, "killed\n")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}

private actor ScriptedRunner: SSHCommandRunner {
    struct Scripted: Sendable {
        let lines: String
        let fails: Bool
    }

    private var streams: [Scripted]
    private(set) var streamed: [String] = []

    init(streams: [Scripted]) { self.streams = streams }

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }

    private func next(_ command: String) -> Scripted {
        streamed.append(command)
        return streams.isEmpty ? Scripted(lines: "", fails: false) : streams.removeFirst()
    }

    nonisolated func stream(_ command: String, on host: SSHHostID,
                            timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let scripted = await self.next(command)
                continuation.yield(.stdout(scripted.lines))
                continuation.yield(.stderr("tail: noise\n"))
                continuation.finish(throwing: scripted.fails ? URLError(.networkConnectionLost) : nil)
            }
        }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {}

    func disconnect() async {}
}

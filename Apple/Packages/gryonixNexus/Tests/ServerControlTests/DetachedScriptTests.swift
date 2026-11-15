import Foundation
import XCTest

@testable import ServerControl

final class DetachedScriptTests: XCTestCase {
    func testTheScriptRunsFromATemporaryFileAndIsRemoved() {
        let command = DetachedScript.command(for: "echo hi\n", elevated: true)
        XCTAssertTrue(command.contains(Data("echo hi\n".utf8).base64EncodedString()))
        XCTAssertTrue(command.contains("sudo -n bash \"$f\""))
        XCTAssertTrue(command.contains("rm -f \"$f\""))
        XCTAssertFalse(DetachedScript.command(for: "true", elevated: false).contains("sudo"))
    }

    func testTheShellThatRunsItStillReportsTheExitCode() throws {
        let command = DetachedScript.command(for: "echo hi\nexit 3\n", elevated: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command + "; echo END:$?"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(text, "hi\nEND:3\n")
    }

    func testTheOutputSurvivesADroppedLink() async throws {
        let runner = DroppingRunner(streams: [
            ("down 1 200\n", true),
            ("up 2 200\nDONE\n\(DetachedJobs.exitMarker)0\n", false),
        ])
        let output = try await DetachedScript.output(of: "true", elevated: false, subject: "speed",
                                                     on: .vps, runner: runner)
        XCTAssertEqual(output, "down 1 200\nup 2 200\nDONE\n")
        let started = await runner.started
        XCTAssertTrue(started.first?.contains("measure-speed-") == true)
        let follows = await runner.followed
        XCTAssertEqual(follows.count, 2)
        XCTAssertTrue(follows[1].contains("n=2"))
    }

    func testMeasurementsAreNotListedAsOtherKinds() {
        let jobs = DetachedJobs.parseList("measure-speed-100 -\n")
        XCTAssertEqual(jobs.first?.kind, .measure)
    }
}

private actor DroppingRunner: SSHCommandRunner {
    private var streams: [(String, Bool)]
    private(set) var started: [String] = []
    private(set) var followed: [String] = []

    init(streams: [(String, Bool)]) { self.streams = streams }

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        started.append(command)
        return ExecResult(exitCode: 0, stdout: "", stderr: "")
    }

    private func next(_ command: String) -> (String, Bool) {
        followed.append(command)
        return streams.isEmpty ? ("", false) : streams.removeFirst()
    }

    nonisolated func stream(_ command: String, on host: SSHHostID,
                            timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let (lines, fails) = await self.next(command)
                continuation.yield(.stdout(lines))
                continuation.finish(throwing: fails ? URLError(.networkConnectionLost) : nil)
            }
        }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {}

    func run(_ command: String, feeding secret: String, on host: SSHHostID,
             timeout: Duration) async throws -> ExecResult {
        try await run(command, on: host, timeout: timeout)
    }

    func disconnect() async {}
}

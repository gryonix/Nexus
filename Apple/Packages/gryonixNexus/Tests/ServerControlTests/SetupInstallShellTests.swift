import XCTest
@testable import ServerControl

/// Runs SetupInstaller's ACTUAL generated commands through a real shell
final class SetupInstallShellTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gryonix-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try installGNUBase64Shim()
    }

    /// The scripts target Debian, where `base64 -d FILE` reads FILE
    private func installGNUBase64Shim() throws {
        let bin = work.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let shim = """
        #!/bin/bash
        last="${@: -1}"
        if [ "$#" -gt 0 ] && [ -f "$last" ]; then
          exec /usr/bin/base64 "${@:1:$#-1}" -i "$last"
        fi
        exec /usr/bin/base64 "$@"
        """
        let path = bin.appendingPathComponent("base64")
        try shim.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    private var shimmedPath: String {
        work.appendingPathComponent("bin").path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    @discardableResult
    private func bash(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = work
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = shimmedPath
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private let fileName = "it's a setup.sh"

    private func writeScript(_ body: String) throws {
        try body.write(to: work.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
    }

    func testGeneratedLaunchCommandRunsTheScript() async throws {
        try writeScript("""
        #!/usr/bin/env bash
        echo "GRYONIXNEXUS_STEP 1/1"
        echo "==> Firewall"
        echo "GRYONIXNEXUS_DONE"
        """)
        let fake = FakeSSHCommandRunner()
        let launch = try await capturedLaunchCommand(fake)
        try bash(launch)
        try await Task.sleep(for: .milliseconds(600))
        let log = try String(contentsOf: work.appendingPathComponent(fileName + ".log"), encoding: .utf8)
        XCTAssertTrue(log.contains("GRYONIXNEXUS_STEP 1/1"), "log was not produced: [\(log)]")
        XCTAssertTrue(log.contains("GRYONIXNEXUS_DONE"))
        XCTAssertTrue(log.contains("GRYONIXNEXUS_EXIT:0"), "exit sentinel missing: [\(log)]")
    }

    func testGeneratedLaunchCommandReportsANonZeroExit() async throws {
        try writeScript("#!/usr/bin/env bash\necho boom >&2\nexit 7\n")
        let fake = FakeSSHCommandRunner()
        let launch = try await capturedLaunchCommand(fake)
        try bash(launch)
        try await Task.sleep(for: .milliseconds(600))
        let log = try String(contentsOf: work.appendingPathComponent(fileName + ".log"), encoding: .utf8)
        XCTAssertTrue(log.contains("boom"), "stderr must land in the log too")
        XCTAssertTrue(log.contains("GRYONIXNEXUS_EXIT:7"), "wrong sentinel: [\(log)]")
    }

    func testLaunchDoesNotLeakItsUmaskIntoTheScript() async throws {
        try writeScript("""
        #!/usr/bin/env bash
        umask > umask.txt
        """)
        let ambient = try bash("umask").trimmingCharacters(in: .whitespacesAndNewlines)
        let fake = FakeSSHCommandRunner()
        let launch = try await capturedLaunchCommand(fake)
        try bash(launch)
        try await Task.sleep(for: .milliseconds(600))
        let seen = try String(contentsOf: work.appendingPathComponent("umask.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(seen, ambient, "the launcher's 077 leaked into the run")
        let mode = try FileManager.default
            .attributesOfItem(atPath: work.appendingPathComponent(fileName + ".log").path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600, "the run log must stay private")
    }

    func testGeneratedFollowCommandResumesAtAnOffsetAndExits() throws {
        let log = work.appendingPathComponent(fileName + ".log")
        try "one\ntwo\nthree\nGRYONIXNEXUS_EXIT:0\n".write(to: log, atomically: true, encoding: .utf8)

        let all = try bash(SetupInstaller.followCommand(fileName: fileName, fromLine: 1))
        XCTAssertEqual(all, "one\ntwo\nthree\nGRYONIXNEXUS_EXIT:0\n")

        let resumed = try bash(SetupInstaller.followCommand(fileName: fileName, fromLine: 3))
        XCTAssertEqual(resumed, "three\nGRYONIXNEXUS_EXIT:0\n",
                       "resume must start exactly at the requested line")
    }

    func testFullInstallThroughARealShell() async throws {
        let runner = LocalShellRunner(directory: work, path: shimmedPath)
        let installer = SetupInstaller(runner: runner, sleeper: FakeSleeper())
        let script = """
        #!/usr/bin/env bash
        echo "GRYONIXNEXUS_STEP 1/2"
        echo "==> Firewall"
        echo "GRYONIXNEXUS_STEP 2/2"
        echo "GRYONIXNEXUS_REPORT_BEGIN"
        echo "Password: hunter2"
        echo "GRYONIXNEXUS_REPORT_END"
        echo "GRYONIXNEXUS_DONE"

        """
        var events: [SetupEvent] = []
        for try await event in installer.install(script: script, fileName: fileName) {
            events.append(event)
        }
        XCTAssertTrue(events.contains(.step(index: 1, total: 2)))
        XCTAssertTrue(events.contains(.stage("Firewall")))
        XCTAssertTrue(events.contains(.report("Password: hunter2")))
        XCTAssertEqual(events.last, .done)
        XCTAssertFalse(events.contains { if case .line(let l) = $0 { return l.contains("GRYONIXNEXUS_EXIT") }; return false })
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent(fileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent(fileName + ".log").path))
    }

    func testInstallSurvivesADroppedFollowerAndResumes() async throws {
        let runner = LocalShellRunner(directory: work, path: shimmedPath)
        runner.failStreamAttempts = [1]
        let installer = SetupInstaller(runner: runner, sleeper: FakeSleeper())
        let script = """
        #!/usr/bin/env bash
        echo "GRYONIXNEXUS_STEP 1/2"
        sleep 2
        echo "GRYONIXNEXUS_STEP 2/2"
        echo "GRYONIXNEXUS_DONE"

        """
        var events: [SetupEvent] = []
        for try await event in installer.install(script: script, fileName: fileName) {
            events.append(event)
        }
        XCTAssertTrue(events.contains(.reconnecting(attempt: 1)), "the drop must be visible")
        XCTAssertTrue(events.contains(.step(index: 1, total: 2)))
        XCTAssertTrue(events.contains(.step(index: 2, total: 2)), "output after the drop was lost")
        XCTAssertEqual(events.last, .done)
        // Nothing delivered twice across the seam.
        let steps = events.filter { if case .step = $0 { return true }; return false }
        XCTAssertEqual(steps.count, 2, "lines were duplicated across the re-attach")
    }
}

private final class LocalShellRunner: SSHCommandRunner, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var streamAttempt = 0
    var failStreamAttempts: Set<Int> = []

    private let path: String

    init(directory: URL, path: String) {
        self.directory = directory
        self.path = path
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        return env
    }

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        let (out, err, code) = exec(command)
        return ExecResult(exitCode: code, stdout: out, stderr: err)
    }

    func run(_ command: String, feeding secret: String, on host: SSHHostID,
             timeout: Duration) async throws -> ExecResult {
        let (out, err, code) = exec(command, stdin: Data(secret.utf8))
        return ExecResult(exitCode: code, stdout: out, stderr: err)
    }

    func stream(_ command: String, on host: SSHHostID, timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        lock.lock()
        streamAttempt += 1
        let cutOff = failStreamAttempts.contains(streamAttempt)
        lock.unlock()

        let directory = self.directory
        let env = environment()
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                process.currentDirectoryURL = directory
                process.environment = env
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do { try process.run() } catch {
                    continuation.finish(throwing: error); return
                }
                let handle = pipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    continuation.yield(.stdout(String(decoding: data, as: UTF8.self)))
                    if cutOff {
                        process.terminate()
                        continuation.finish()
                        return
                    }
                }
                process.waitUntilExit()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws { _ = exec(command) }
    func disconnect() async {}

    private func exec(_ command: String, stdin: Data = Data()) -> (String, String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        process.environment = environment()
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        do { try process.run() } catch { return ("", "\(error)", 127) }
        input.fileHandleForWriting.write(stdin)
        try? input.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self),
                process.terminationStatus)
    }
}

private extension SetupInstallShellTests {
    func capturedLaunchCommand(_ fake: FakeSSHCommandRunner) async throws -> String {
        fake.stub("cat > ")
        fake.stub("setsid")
        fake.stub("wc -l", stdout: "GRYONIXNEXUS_DONE\nGRYONIXNEXUS_EXIT:0\n")
        fake.stub("rm -f")
        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        for try await _ in installer.install(script: "x\n", fileName: fileName) {}
        return try XCTUnwrap(fake.calls.map(\.command).first { $0.contains("DETACH") })
    }
}

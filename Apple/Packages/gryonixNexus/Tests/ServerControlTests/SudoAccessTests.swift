import XCTest
@testable import ServerControl

final class SudoAccessTests: XCTestCase {
    func testTheProbeTokenIsReadOnlyAsAWholeLine() {
        XCTAssertTrue(SudoAccess.isReady("GRYONIXNEXUS_PING\nGRYONIXNEXUS_SUDO_OK\n"))
        XCTAssertFalse(SudoAccess.isReady("echo GRYONIXNEXUS_SUDO_OK_NOT"))
        XCTAssertFalse(SudoAccess.isReady(""))
    }

    func testSudoWordingsMapToOutcomes() {
        func outcome(_ code: Int32, _ out: String, _ err: String) -> SudoAccess.Outcome {
            SudoAccess.outcome(of: ExecResult(exitCode: code, stdout: out, stderr: err))
        }
        XCTAssertEqual(outcome(0, "GRYONIXNEXUS_SUDO_OK\n", ""), .granted)
        XCTAssertEqual(outcome(1, "", "Sorry, try again.\nsudo: 1 incorrect password attempt\n"),
                       .wrongPassword)
        XCTAssertEqual(outcome(1, "", "sudo: no password was provided\n"), .wrongPassword)
        XCTAssertEqual(outcome(1, "", "anna is not in the sudoers file.\n"), .notAllowed)
        XCTAssertEqual(outcome(1, "", "Sorry, user anna is not allowed to run sudo on draco.\n"),
                       .notAllowed)
        XCTAssertEqual(outcome(3, "", "visudo: parse error\n"), .failed("visudo: parse error"))
    }

    func testAnInsultInPlaceOfSorryIsStillAWrongPassword() {
        let insult = ExecResult(exitCode: 1, stdout: "",
                                stderr: "sudo: I'm sorry server-user. I'm afraid I can't do that\n")
        XCTAssertEqual(SudoAccess.outcome(of: insult), .wrongPassword)
    }

    func testALockedAccountIsToldApartFromAnOpenOne() {
        XCTAssertTrue(SudoAccess.passwordIsLocked("GRYONIXNEXUS_PASSWORD=L\n"))
        XCTAssertTrue(SudoAccess.passwordIsLocked("GRYONIXNEXUS_PASSWORD=NP\n"))
        XCTAssertFalse(SudoAccess.passwordIsLocked("GRYONIXNEXUS_PASSWORD=P\n"))
        XCTAssertFalse(SudoAccess.passwordIsLocked(""))
    }

    func testTheAgentProbeAcceptsAWhitelistedWrapper() {
        let probe = SudoAccess.probeCommand(allowing: "/opt/gryonixnexus-agent-bootstrap.sh")
        XCTAssertTrue(probe.contains("sudo -n -l '/opt/gryonixnexus-agent-bootstrap.sh'"))
        XCTAssertTrue(probe.contains("passwd -S"))
    }

    func testANewerSudoRefusalReadsAsAPasswordPrompt() {
        XCTAssertTrue(ServerControlError.stderrAsksForASudoPassword(
            "sudo: interactive authentication is required\n"))
    }

    func testThePasswordGoesByFileAndNeverIntoACommand() async throws {
        let runner = FakeFileRunner()
        runner.stub("mktemp -d", stdout: "/tmp/tmp.AbC123\n")
        runner.stub("sudo -S", stdout: "GRYONIXNEXUS_SUDO_OK\n")
        let outcome = try await SudoAccess.grant(password: "s3cret pass", runner: runner, host: .vps)

        XCTAssertEqual(outcome, .granted)
        XCTAssertEqual(runner.uploads.map(\.path), ["/tmp/tmp.AbC123/p"])
        XCTAssertEqual(runner.uploads.first?.data, Data("s3cret pass\n".utf8))
        XCTAssertFalse(runner.calls.contains { $0.command.contains("s3cret") })
        XCTAssertTrue(runner.calls.last?.command.hasSuffix("rm -rf '/tmp/tmp.AbC123'; exit $rc") == true)
    }

    func testAFailedUploadStillRemovesTheDirectory() async {
        let runner = FakeFileRunner()
        runner.stub("mktemp -d", stdout: "/tmp/tmp.X\n")
        runner.uploadError = ServerControlError.connectionFailed("sftp")
        do {
            _ = try await SudoAccess.grant(password: "p", runner: runner, host: .vps)
            XCTFail("expected the upload error")
        } catch {
            XCTAssertEqual(runner.calls.last?.command, "rm -rf '/tmp/tmp.X'")
        }
    }

    func testTheGrantLineWritesTheDropInAndWipesThePassword() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("gryonix-sudo-\(UUID().uuidString)")
        let bin = work.appendingPathComponent("bin")
        let drop = work.appendingPathComponent("sudoers.d")
        let staging = work.appendingPathComponent("stage")
        for dir in [bin, drop, staging] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: work) }
        try Data("right\n".utf8).write(to: staging.appendingPathComponent("p"))
        try script("""
        #!/bin/sh
        read -r pw
        [ "$pw" = right ] || { echo "sudo: 1 incorrect password attempt" >&2; exit 1; }
        while [ "$1" != "-c" ]; do shift; done
        body=$(printf %s "$2" | sed "s#/etc/sudoers.d#$DROP#g")
        SUDO_USER=anna.b exec sh -c "$body"
        """, at: bin.appendingPathComponent("sudo"))
        try script("#!/bin/sh\nexit 0\n", at: bin.appendingPathComponent("visudo"))

        let result = try shell(SudoAccess.grantCommand(directory: staging.path),
                               path: bin.path, drop: drop.path)

        XCTAssertEqual(SudoAccess.outcome(of: result), .granted)
        let written = try String(contentsOf: drop.appendingPathComponent("gryonixnexus-anna_b"),
                                 encoding: .utf8)
        XCTAssertEqual(written, "anna.b ALL=(ALL) NOPASSWD:ALL\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    private func script(_ text: String, at url: URL) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func shell(_ command: String, path: String, drop: String) throws -> ExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": "\(path):/usr/bin:/bin", "DROP": drop]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return ExecResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}

/// A fake runner that also records SFTP uploads
private final class FakeFileRunner: FakeSSHCommandRunner, RemoteFileBrowser, @unchecked Sendable {
    private(set) var uploads: [(path: String, data: Data)] = []
    var uploadError: Error?

    func homeDirectory(on host: SSHHostID) async throws -> String { "/home/anna" }
    func listDirectory(_ path: String, on host: SSHHostID) async throws -> [RemoteFileEntry] { [] }
    func downloadFile(_ path: String, on host: SSHHostID, maxBytes: UInt64) async throws -> Data { Data() }
    func deleteFile(_ entry: RemoteFileEntry, on host: SSHHostID) async throws {}

    func uploadFile(_ data: Data, to path: String, on host: SSHHostID) async throws {
        if let uploadError { throw uploadError }
        uploads.append((path, data))
    }
}

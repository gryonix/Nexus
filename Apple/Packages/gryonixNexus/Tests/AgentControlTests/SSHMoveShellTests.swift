import Foundation
import ServerControl
import XCTest
@testable import AgentControl

private final class LocalRunner: SSHCommandRunner, @unchecked Sendable {
    let home: URL

    init(home: URL) { self.home = home }

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let (out, err) = (Pipe(), Pipe())
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return ExecResult(exitCode: process.terminationStatus,
                          stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                          stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func stream(_ command: String, on host: SSHHostID, timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {}
    func disconnect() async {}
}

final class SSHMoveShellTests: XCTestCase {
    private func makeShell() throws -> (SSHMoveShell, URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("move-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (SSHMoveShell(runner: LocalRunner(home: home), host: .vps, loginUser: "admin"), home)
    }

    private func keys(_ home: URL) throws -> String {
        try String(contentsOf: home.appendingPathComponent(".ssh/authorized_keys"), encoding: .utf8)
    }

    func testTheKeyLineIsAppendedBesideTheKeysAlreadyThere() async throws {
        let (shell, home) = try makeShell()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        try "ssh-ed25519 OLD owner\n".write(to: home.appendingPathComponent(".ssh/authorized_keys"),
                                           atomically: true, encoding: .utf8)
        let line = #"restrict,command="cat > /var/lib/gryonixnexus/incoming/ab/data.tar" ssh-ed25519 NEW gryonixnexus-move-ab"#
        try await shell.appendAuthorizedKey(line)
        XCTAssertEqual(try keys(home), "ssh-ed25519 OLD owner\n\(line)\n")
    }

    func testRemovingTheLineLeavesTheOtherKeysAlone() async throws {
        let (shell, home) = try makeShell()
        defer { try? FileManager.default.removeItem(at: home) }
        try await shell.appendAuthorizedKey("ssh-ed25519 ONE gryonixnexus-move-aa")
        try await shell.appendAuthorizedKey("ssh-ed25519 TWO owner")
        try await shell.appendAuthorizedKey("ssh-ed25519 THREE gryonixnexus-move-bb")
        try await shell.removeAuthorizedKeys(containing: "gryonixnexus-move-aa")
        XCTAssertEqual(try keys(home), "ssh-ed25519 TWO owner\nssh-ed25519 THREE gryonixnexus-move-bb\n")
        try await shell.removeAuthorizedKeys(containing: "gryonixnexus-move-aa")
        try await shell.removeAuthorizedKeys(containing: "gryonixnexus-move-bb")
        XCTAssertEqual(try keys(home), "ssh-ed25519 TWO owner\n")
    }

    func testRemovingFromAMachineWithNoKeyFileIsNotAnError() async throws {
        let (shell, home) = try makeShell()
        defer { try? FileManager.default.removeItem(at: home) }
        try await shell.removeAuthorizedKeys(containing: "gryonixnexus-move-aa")
    }

    func testAQuoteInTheLineCannotBreakOutOfTheCommand() async throws {
        let (shell, home) = try makeShell()
        defer { try? FileManager.default.removeItem(at: home) }
        let line = "ssh-ed25519 A'; touch \(home.path)/pwned; echo '"
        try await shell.appendAuthorizedKey(line)
        XCTAssertEqual(try keys(home), line + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("pwned").path))
    }
}

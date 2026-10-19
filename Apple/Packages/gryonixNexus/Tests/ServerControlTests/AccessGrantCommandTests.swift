import XCTest
@testable import ServerControl

/// Runs the ACTUAL grant one-liner through a real shell
final class AccessGrantCommandTests: XCTestCase {
    private var work: URL!
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGleMByJcadYCpDGjG3xDWDKzY4ufBe8ZLEsmva104tp gryonixnexus-app"

    override func setUpWithError() throws {
        work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gryonix-grant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try installGetentStub()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func installGetentStub() throws {
        let bin = work.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let stub = """
        #!/bin/bash
        # usage: getent passwd <name>
        while IFS=$'\\t' read -r name home; do
          if [ "$name" = "$2" ]; then
            echo "$name:x:1000:1000::$home:/bin/sh"
            exit 0
          fi
        done < "$GRYONIX_PASSWD"
        exit 2
        """
        let path = bin.appendingPathComponent("getent")
        try stub.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    @discardableResult
    private func account(_ name: String) throws -> URL {
        let home = work.appendingPathComponent("home-\(name)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let table = work.appendingPathComponent("passwd")
        let line = "\(name)\t\(home.path)\n"
        if let handle = try? FileHandle(forWritingTo: table) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try line.write(to: table, atomically: true, encoding: .utf8)
        }
        return home
    }

    @discardableResult
    private func runGrant(sudoUser: String? = nil, callerHome: URL? = nil) throws -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", AccessGrantCommand.command(publicKey: key)]
        process.currentDirectoryURL = work
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = work.appendingPathComponent("bin").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GRYONIX_PASSWD"] = work.appendingPathComponent("passwd").path
        if let sudoUser { env["SUDO_USER"] = sudoUser } else { env.removeValue(forKey: "SUDO_USER") }
        if let callerHome { env["HOME"] = callerHome.path }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    // MARK: - Tests

    func testGrantingToTheAccountRunningItWritesAReadableAuthorizedKeysFile() throws {
        let me = ProcessInfo.processInfo.userName
        let home = try account(me)

        let result = try runGrant()

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\(AccessGrantCommand.marker) \(me)"),
                      "the command must name the account it granted: \(result.output)")
        let file = home.appendingPathComponent(".ssh/authorized_keys")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), key + "\n")
        XCTAssertEqual(try mode(of: home.appendingPathComponent(".ssh")), 0o700)
        XCTAssertEqual(try mode(of: file), 0o600)
    }

    func testPastedWithSudoItGrantsTheInvokingAccountAndNotTheElevatedShellsHome() throws {
        let target = try account("admin")
        let rootHome = try account("root")

        let result = try runGrant(sudoUser: "admin", callerHome: rootHome)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\(AccessGrantCommand.marker) admin"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent(".ssh/authorized_keys").path),
                      "the key must land in the account that ran sudo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootHome.appendingPathComponent(".ssh").path),
                       "the elevated shell's own home must be left alone")
    }

    func testRunningItTwiceDoesNotDuplicateTheKey() throws {
        let me = ProcessInfo.processInfo.userName
        let home = try account(me)

        try runGrant()
        let result = try runGrant()

        XCTAssertEqual(result.status, 0, result.output)
        let contents = try String(contentsOf: home.appendingPathComponent(".ssh/authorized_keys"), encoding: .utf8)
        XCTAssertEqual(contents.components(separatedBy: key).count - 1, 1, contents)
    }

    func testAnUnknownAccountFailsInsteadOfWritingToTheFilesystemRoot() throws {
        _ = try account("someone-else")

        let result = try runGrant(sudoUser: "not-a-user")

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("no home directory for not-a-user"), result.output)
    }

    func testTheCommandIsOneSudoableUnitAndNeverReliesOnTildeExpansion() {
        let command = AccessGrantCommand.command(publicKey: key)

        XCTAssertTrue(command.hasPrefix("sh -c '"), command)
        XCTAssertTrue(command.hasSuffix("'"), command)
        let payload = command.dropFirst("sh -c '".count).dropLast()
        XCTAssertFalse(payload.replacingOccurrences(of: "'\\''", with: "").contains("'"),
                       "the payload must stay a single shell word")
        XCTAssertFalse(command.contains("~"), command)
        XCTAssertFalse(command.contains("$HOME"), command)
    }
}

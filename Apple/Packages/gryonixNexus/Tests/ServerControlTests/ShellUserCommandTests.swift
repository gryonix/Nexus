import XCTest
@testable import ServerControl

/// Runs the ACTUAL account-creation one-liner through a real shell
final class ShellUserCommandTests: XCTestCase {
    private var work: URL!
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGleMByJcadYCpDGjG3xDWDKzY4ufBe8ZLEsmva104tp gryonixnexus-app"

    override func setUpWithError() throws {
        work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gryonix-user-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try installStubs()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func installStubs() throws {
        let bin = work.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let table = work.appendingPathComponent("passwd").path
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("home"), withIntermediateDirectories: true)

        try write("""
        #!/bin/bash
        # usage: getent passwd <name>
        [ -f "$GRYONIX_PASSWD" ] || exit 2
        while IFS=$'\\t' read -r name home; do
          if [ "$name" = "$2" ]; then
            echo "$name:x:1000:1000::$home:/bin/bash"
            exit 0
          fi
        done < "$GRYONIX_PASSWD"
        exit 2
        """, to: bin.appendingPathComponent("getent"))

        try write("""
        #!/bin/bash
        # usage: useradd -m -s /bin/bash <name>
        name="${@: -1}"
        home="$GRYONIX_HOMES/$name"
        mkdir -p "$home"
        printf '%s\\t%s\\n' "$name" "$home" >> "\(table)"
        """, to: bin.appendingPathComponent("useradd"))

        try write("#!/bin/bash\nexit 0\n", to: bin.appendingPathComponent("chown"))

        try write("""
        #!/bin/bash
        # usage: id <name>  /  id -u
        if [ "$1" = "-u" ]; then echo 1000; exit 0; fi
        grep -q "^$1\\b" "$GRYONIX_PASSWD" 2>/dev/null || exit 1
        """, to: bin.appendingPathComponent("id"))
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
    }

    @discardableResult
    private func run(name: String, sudo: Bool = false) throws -> (output: String, status: Int32) {
        let command = try XCTUnwrap(ShellUserCommand.command(name: name, publicKey: key, sudo: sudo))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = work
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = work.appendingPathComponent("bin").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GRYONIX_PASSWD"] = work.appendingPathComponent("passwd").path
        env["GRYONIX_HOMES"] = work.appendingPathComponent("home").path
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

    func testItCreatesTheAccountWithAKeyItCanSignInWith() throws {
        let result = try run(name: "dana")

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\(ShellUserCommand.marker) dana"),
                      "it must name the account it created: \(result.output)")
        let home = work.appendingPathComponent("home/dana")
        let file = home.appendingPathComponent(".ssh/authorized_keys")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), key + "\n")
        XCTAssertEqual(try mode(of: home.appendingPathComponent(".ssh")), 0o700)
        XCTAssertEqual(try mode(of: file), 0o600)
    }

    func testRunningItTwiceLeavesOneAccountAndOneKey() throws {
        try run(name: "dana")
        let second = try run(name: "dana")

        XCTAssertEqual(second.status, 0, second.output)
        let file = work.appendingPathComponent("home/dana/.ssh/authorized_keys")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), key + "\n")
    }

    func testTheWholeThingIsOneShellWord() throws {
        let command = try XCTUnwrap(ShellUserCommand.command(name: "dana", publicKey: key, sudo: true))
        XCTAssertTrue(command.hasPrefix("sh -c '"), command)
        XCTAssertTrue(command.hasSuffix("'"), command)
        let payload = command.dropFirst("sh -c '".count).dropLast()
        XCTAssertFalse(payload.replacingOccurrences(of: "'\\''", with: "").contains("'"),
                       "a nested, unescaped single quote would end the payload early")
    }

    func testSudoIsStagedAndValidatedBeforeItIsLive() throws {
        let command = try XCTUnwrap(ShellUserCommand.command(name: "dana", publicKey: key, sudo: true))
        let staged = command.range(of: "/etc/sudoers.d/.gryonixnexus-$u.tmp")
        let validated = command.range(of: "visudo -cf")
        let moved = command.range(of: "mv \"$t\" /etc/sudoers.d/gryonixnexus-$u")
        XCTAssertNotNil(staged)
        XCTAssertNotNil(validated)
        XCTAssertNotNil(moved)
        XCTAssertTrue(staged!.upperBound < validated!.lowerBound,
                      "the file must exist before it is checked")
        XCTAssertTrue(validated!.upperBound < moved!.lowerBound,
                      "it must be checked before it is live")
    }

    func testWithoutSudoNothingTouchesTheSudoersDirectory() throws {
        let command = try XCTUnwrap(ShellUserCommand.command(name: "dana", publicKey: key, sudo: false))
        XCTAssertFalse(command.contains("sudoers"))
    }

    func testOnlyNamesLinuxAcceptsAndWeAreWillingToCreate() {
        XCTAssertTrue(ShellUserCommand.isValidName("dana"))
        XCTAssertTrue(ShellUserCommand.isValidName("build-bot_2"))
        XCTAssertFalse(ShellUserCommand.isValidName(""))
        XCTAssertFalse(ShellUserCommand.isValidName("Dana"), "upper case is not a Linux login")
        XCTAssertFalse(ShellUserCommand.isValidName("2fast"), "must start with a letter")
        XCTAssertFalse(ShellUserCommand.isValidName("da na"))
        XCTAssertFalse(ShellUserCommand.isValidName("da'na"))
        XCTAssertFalse(ShellUserCommand.isValidName("da;rm -rf /"))
        XCTAssertFalse(ShellUserCommand.isValidName(String(repeating: "a", count: 33)))
    }

    func testAnExistingSystemAccountIsNotSomethingThisCreates() {
        XCTAssertFalse(ShellUserCommand.isValidName("root"))
        XCTAssertFalse(ShellUserCommand.isValidName("sshd"))
        XCTAssertFalse(ShellUserCommand.isValidName("docker"))
        XCTAssertNil(ShellUserCommand.command(name: "root", publicKey: key, sudo: false),
                     "a caller that ignored the guard must get nothing to run")
    }
}

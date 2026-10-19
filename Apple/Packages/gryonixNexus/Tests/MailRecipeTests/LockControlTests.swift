import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class LockControlTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    private let mixed: Set<ServiceID> = [.nextcloud, .immich, .vaultwarden, .jellyfin,
                                         .gitlab, .amneziaWG]

    private func script(_ services: Set<ServiceID>, file: String = "setup-mail-server.sh") throws -> String {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: appKey),
            services: services,
            serviceSettings: ServiceSettings(wireguardVPNPort: 51821)
        )
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == file }?.contents,
                             bundle.artifacts.map(\.fileName).joined(separator: ", "))
    }

    private func wrapperBody(in script: String, scriptPath: String, delimiter: String) -> String {
        let start = "cat > \(scriptPath) <<'\(delimiter)'"
        guard let range = script.range(of: start),
              let end = script.range(of: "\n\(delimiter)\n", range: range.upperBound..<script.endIndex)
        else { return "" }
        return String(script[range.upperBound..<end.lowerBound])
    }

    private func backupWrapper(in script: String) -> String {
        wrapperBody(in: script, scriptPath: BackupControlSections.scriptPath, delimiter: "EOF_BACKUP_CTL")
    }

    private func updateWrapper(in script: String) -> String {
        wrapperBody(in: script, scriptPath: UpdateControlSections.scriptPath, delimiter: "EOF_UPDATE_CTL")
    }

    // MARK: - The shared helper

    func testBothWrappersCarryTheIdenticalLockHelper() throws {
        let text = try script(mixed)
        XCTAssertEqual(text.components(separatedBy: "gd_with_lock() {").count - 1, 2,
                       "both wrappers must define the lock helper — one copy each, no third place")
        XCTAssertTrue(text.contains("GD_LOCK_BUSY=75"))
        XCTAssertTrue(text.contains("flock -n \"$fd\""),
                      "the acquire must be non-blocking: a scheduled run must never hang on a lock")
        XCTAssertTrue(text.contains("install -d -m 700 '\(LockSections.directory)'"),
                      "the lock directory must be root-only — nobody else reaches either wrapper")
    }

    // MARK: - Backup: every dispatch arm is lock-guarded

    func testEveryBackupDispatchArmAcquiresItsOwnLockFirst() throws {
        let wrapper = backupWrapper(in: try script(mixed))
        let dispatchStart = try XCTUnwrap(wrapper.range(of: "gd_run_service() {"))
        let dispatchEnd = try XCTUnwrap(wrapper.range(of: "\n}\n", range: dispatchStart.upperBound..<wrapper.endIndex))
        let dispatch = String(wrapper[dispatchStart.upperBound..<dispatchEnd.lowerBound])
        var arms = 0
        for rawLine in dispatch.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix(";;"), !line.hasPrefix("*)"), let paren = line.firstIndex(of: ")") else { continue }
            let label = String(line[line.startIndex..<paren])
            arms += 1
            XCTAssertTrue(line.contains("gd_with_lock 'backup-\(label)' backup_"),
                          "the \(label) arm must take the backup-\(label) lock before running its body: \(line)")
        }
        XCTAssertGreaterThanOrEqual(arms, 4, "the dispatch table lost its arms — this test would now pass on nothing")
    }

    // MARK: - Update: the per-service body runs under its own lock

    func testUpdateServiceAcquiresItsOwnLockBeforeRunning() throws {
        let wrapper = updateWrapper(in: try script(mixed))
        XCTAssertTrue(wrapper.contains(#"gd_with_lock "update-$svc" gd_update_service_locked "$svc""#),
                      "the entry point must hand off to the locked body under its own lock")
        XCTAssertTrue(wrapper.contains("gd_update_service_locked() {"))
    }

    func testALockCollisionDuringAnUpdateIsRecordedNotJustLogged() throws {
        let wrapper = updateWrapper(in: try script(mixed))
        let entryStart = try XCTUnwrap(wrapper.range(of: "gd_update_service() {"))
        let entryEnd = try XCTUnwrap(wrapper.range(of: "\n}\n", range: entryStart.upperBound..<wrapper.endIndex))
        let body = String(wrapper[entryStart.upperBound..<entryEnd.lowerBound])
        XCTAssertTrue(body.contains(#"[ "$rc" -eq "$GD_LOCK_BUSY" ]"#),
                      "a lock collision must be told apart from every other failure")
        XCTAssertTrue(body.contains("'\(UpdateControlSections.failedMarker)' \"$svc\""),
                      "a collision must land in the SAME structural marker every other pre-image-swap "
                        + "failure uses")
    }

    // MARK: - The two lock namespaces never collide

    func testTheUpdateLockIsAcquiredExactlyOncePerInvocation() throws {
        let wrapper = updateWrapper(in: try script(mixed))
        XCTAssertEqual(wrapper.components(separatedBy: "\"update-$svc\"").count - 1, 1,
                       "the update lock must be acquired exactly once per invocation, "
                         + "never again inside the body it guards")
    }

    // MARK: - Syntax

    #if os(macOS)
    func testTheGeneratedBackupWrapperIsValidBash() throws {
        try assertValidBash(backupWrapper(in: try script(mixed)), name: "gryonixnexus-backup-ctl")
    }

    func testTheGeneratedUpdateWrapperIsValidBashWithLocking() throws {
        try assertValidBash(updateWrapper(in: try script(mixed)), name: "gryonixnexus-update-ctl")
    }

    private func assertValidBash(_ body: String, name: String) throws {
        XCTAssertFalse(body.isEmpty, "\(name): nothing was extracted")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).sh")
        try body.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", url.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "\(name): bash -n failed:\n\(message)")
    }
    #endif
}

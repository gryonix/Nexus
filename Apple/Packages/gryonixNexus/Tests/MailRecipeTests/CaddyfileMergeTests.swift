import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class CaddyfileMergeTests: XCTestCase {
    // MARK: - Running the merge

    private struct MergeResult {
        let kept: String
        let clashes: String
    }

    private func merge(ours: String, existing: String, ourIDs: String) throws -> MergeResult {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("caddy-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oursURL = directory.appendingPathComponent("ours")
        let existingURL = directory.appendingPathComponent("existing")
        let keptURL = directory.appendingPathComponent("kept")
        try ours.write(to: oursURL, atomically: true, encoding: .utf8)
        try existing.write(to: existingURL, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: keptURL.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        process.arguments = ["-v", "ourids=\(ourIDs)",
                             "-v", "out=\(keptURL.path)",
                             ServiceInfraSections.caddyMergeAWK,
                             oursURL.path, existingURL.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0,
                       "awk failed: \(String(data: stderr, encoding: .utf8) ?? "")")

        return MergeResult(
            kept: (try? String(contentsOf: keptURL, encoding: .utf8)) ?? "",
            clashes: (String(data: stdout, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func oursFile(names: String = "chat.example.com",
                          owner: String = "open-webui") -> String {
        ServiceInfraSections.caddyGlobalOptions + "\n\n"
            + ServiceInfraSections.caddySite(owner: owner, hostname: names, upstreamPort: 3000)
            + "\n"
    }

    private func strangerSite(names: String, port: Int = 9000) -> String {
        """
        \(names) {
            reverse_proxy 127.0.0.1:\(port)
        }
        """
    }

    // MARK: - What must survive

    /// The defect itself
    func testAStrangersSiteSurvivesTheInstall() throws {
        let existing = ServiceInfraSections.caddyGlobalOptions + "\n\n"
            + strangerSite(names: "pihole.example.com") + "\n\n"
            + strangerSite(names: "old.example.com", port: 9001) + "\n"

        let result = try merge(ours: oursFile(), existing: existing, ourIDs: "open-webui")

        XCTAssertEqual(result.clashes, "", "nothing here claims a name we serve")
        XCTAssertTrue(result.kept.contains("pihole.example.com {"),
                      "a site this deployment never wrote was dropped: \(result.kept)")
        XCTAssertTrue(result.kept.contains("old.example.com {"),
                      "a site this deployment never wrote was dropped: \(result.kept)")
        XCTAssertTrue(result.kept.contains("reverse_proxy 127.0.0.1:9001"),
                      "a kept block lost its body")
    }

    func testTheKeptBlocksConcatenateOntoOurFile() throws {
        let ours = oursFile()
        let result = try merge(ours: ours,
                               existing: strangerSite(names: "pihole.example.com") + "\n",
                               ourIDs: "open-webui")
        let merged = ours + result.kept

        XCTAssertFalse(merged.contains("}\npihole"), "blocks ran together with no blank line")
        XCTAssertFalse(merged.contains("\n\n\n"), "blocks were separated by more than one blank line")
        XCTAssertEqual(merged.components(separatedBy: ServiceInfraSections.caddyGlobalOptions).count - 1, 1,
                       "the merged file carries the global block once")
    }

    // MARK: - What must not

    func testOurOwnBlockIsNotKeptTwice() throws {
        let ours = oursFile()
        let result = try merge(ours: ours, existing: ours, ourIDs: "open-webui")

        XCTAssertEqual(result.kept, "", "our own previous block was kept as a stranger's")
        XCTAssertEqual(result.clashes, "", "our own block was reported as a collision with itself")
    }

    func testOurBlockUnderAnOldHostnameIsDropped() throws {
        let existing = ServiceInfraSections.caddySite(owner: "open-webui",
                                                      hostname: "ai.example.com",
                                                      upstreamPort: 3000) + "\n"
        let result = try merge(ours: oursFile(), existing: existing, ourIDs: "open-webui")

        XCTAssertEqual(result.kept, "",
                       "the site we moved off is still served by a block nothing updates")
    }

    func testAnUnmarkedBlockWithOurHeaderIsOurs() throws {
        let result = try merge(ours: oursFile(),
                               existing: strangerSite(names: "chat.example.com") + "\n",
                               ourIDs: "open-webui")

        XCTAssertEqual(result.kept, "", "an unmarked block on our own name was kept beside ours")
        XCTAssertEqual(result.clashes, "",
                       "an unmarked block on our own name was refused as a stranger's")
    }

    func testTheHostsOwnGlobalBlockIsDropped() throws {
        let result = try merge(ours: oursFile(),
                               existing: ServiceInfraSections.caddyGlobalOptions + "\n",
                               ourIDs: "open-webui")

        XCTAssertEqual(result.kept, "", "the host's global block was kept beside ours")
    }

    // MARK: - The refusal

    func testANameAStrangerAlreadyServesStopsTheRun() throws {
        let result = try merge(ours: oursFile(names: "chat.example.com, chat.example.org"),
                               existing: strangerSite(names: "chat.example.org") + "\n",
                               ourIDs: "open-webui")

        XCTAssertEqual(result.clashes, "chat.example.org",
                       "a name another block already serves was not reported")
    }

    func testEveryClashingNameIsNamedOnce() throws {
        let existing = strangerSite(names: "chat.example.com, a.example.com") + "\n\n"
            + strangerSite(names: "chat.example.com, b.example.com", port: 9002) + "\n"
        let result = try merge(ours: oursFile(names: "chat.example.com"),
                               existing: existing,
                               ourIDs: "open-webui")

        XCTAssertEqual(result.clashes, "chat.example.com")
    }

    func testTheLastBlockOfOurFileIsNotGluedToTheHostsFirst() throws {
        let result = try merge(ours: oursFile(names: "chat.example.com"),
                               existing: strangerSite(names: "pihole.example.com") + "\n",
                               ourIDs: "open-webui")

        XCTAssertFalse(result.kept.contains("chat.example.com"),
                       "our own last site came back as part of a kept block: \(result.kept)")
        XCTAssertTrue(result.kept.contains("pihole.example.com {"),
                      "the host's first block was swallowed: \(result.kept)")
    }

    // MARK: - The script that runs it

    func testTheGeneratedScriptRunsTheMergeBeforeReplacingTheFile() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            dashboardAccess: DashboardAccessInput(sshUser: "admin",
                                                  appPublicKey: "ssh-ed25519 AAAAKEY app"),
            services: [.vaultwarden],
            serviceSettings: ServiceSettings(),
            language: .en
        )
        let script = ServiceInfraSections.writeCaddyfile(
            MailContext(input: input, renderer: StringTemplateRenderer()))

        XCTAssertTrue(script.contains("' /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile)"),
                      "the merge does not read our file first and the host's second")
        guard let mergeIndex = script.range(of: "caddy_clash=$(awk")?.lowerBound,
              let moveIndex = script.range(of: "mv /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile")?.lowerBound
        else { return XCTFail("the section no longer merges, or no longer installs the result") }
        XCTAssertLessThan(mergeIndex, moveIndex,
                          "the file is replaced before the host's own blocks are read out of it")
        XCTAssertTrue(script.contains("backup /etc/caddy/Caddyfile"),
                      "the previous file is replaced without a copy beside it")
    }
}

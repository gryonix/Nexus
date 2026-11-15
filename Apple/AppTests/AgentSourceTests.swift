import XCTest

@testable import gryonixNexus

/// The agent comes from the app or the repository
final class AgentSourceTests: XCTestCase {
    private let archive = "/home/server-user/gryonixnexus-agent-src.tar.gz"

    func testTheAppsOwnSourcesFetchNothing() {
        XCTAssertNil(AgentSource.app.branch)
        XCTAssertNil(AgentSource.app.fetchScript(archivePath: archive),
                     "the app uploads its own archive — there is nothing to fetch")
    }

    func testTheKnownBranches() {
        XCTAssertEqual(AgentSource.repositoryMain.branch, "main")
        XCTAssertEqual(AgentSource.repositoryBeta.branch, "beta")
        XCTAssertEqual(AgentSource.repositoryWip.branch, "wip")
        XCTAssertEqual(AgentSource.allCases.compactMap(\.branch), ["main", "beta", "wip"])
        XCTAssertEqual(AgentSource.named("repositoryWip"), .repositoryWip)
        // Anything else falls back to the app's own sources
        XCTAssertEqual(AgentSource.named("../../etc"), .app)
        XCTAssertEqual(AgentSource.named(""), .app)
    }

    func testTheFetchLeavesTheLayoutTheWrapperExpects() throws {
        let script = try XCTUnwrap(AgentSource.repositoryMain.fetchScript(archivePath: archive))
        XCTAssertTrue(script.contains("codeload.github.com/gryonix/nexus-agent/tar.gz/refs/heads/main"),
                      script)
        XCTAssertTrue(script.contains("-C \"$ROOT\" Agent"),
                      "the archive has to carry the Agent root, like the packed one")
        XCTAssertTrue(script.contains("'\(archive)'"),
                      "the archive path is quoted into the tar call")
    }

    /// A 404 names the private repository, not the branch
    func testAPrivateRepositoryIsNamedForWhatItIs() throws {
        let script = try XCTUnwrap(AgentSource.repositoryMain.fetchScript(archivePath: archive))
        XCTAssertTrue(script.contains("-w '%{http_code}'"),
                      "the status code is what tells 404 from a broken download")
        XCTAssertTrue(script.contains("404)"), script)
        XCTAssertTrue(script.contains("public repository"),
                      "a 404 has to name the remedy, not the curl exit code")
        XCTAssertFalse(script.contains("curl -fsSL"),
                       "`-f` throws the status code away")
    }

    /// A branch without the agent must fail loudly
    func testABranchWithoutTheAgentIsRefused() throws {
        let script = try XCTUnwrap(AgentSource.repositoryBeta.fetchScript(archivePath: archive))
        XCTAssertTrue(script.contains("[ -d \"$ROOT/Agent/gryonixnexusd\" ]"), script)
        XCTAssertTrue(script.contains("set -eu"), "a failing step must end the script")
    }

    /// The branch's version is the crate's own, not a dependency's
    func testTheBranchVersionIsTheCratesFirstVersionLine() {
        let manifest = """
        [package]
        name = "gryonixnexusd"
        version = "26.10.21"
        edition = "2021"

        [dependencies]
        tokio = { version = "1", features = ["full"] }
        """
        XCTAssertEqual(AgentSource.crateVersion(in: manifest), "26.10.21")
        XCTAssertNil(AgentSource.crateVersion(in: "[package]\nname = \"x\""))
    }

    func testTheAppsOwnSourcesReadNoBranch() async {
        let offered = await AgentSource.app.offeredVersion(shipped: "26.10.20")
        XCTAssertEqual(offered, "26.10.20", "the app's own sources offer what the app carries")
    }
}

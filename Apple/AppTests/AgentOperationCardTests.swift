import XCTest
@testable import gryonixNexus

final class AgentOperationCardTests: XCTestCase {
    func testAgentInstallsAndUpdatesStayOffTheLockScreen() throws {
        for path in ["App/Features/Dashboard/DashboardViewModel.swift", "App/Services/AgentUpdateOffer.swift"] {
            let source = try String(contentsOf: Self.repo.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("onLockScreen: false"), "\(path) puts an agent run on the lock screen")
        }
    }

    func testTheAppStaysQuietOnlyWhileTheServerIsHeard() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(LiveActivityJobs.isMoving(led: true, heard: nil, now: now),
                       "a server that never moved the card must not silence the app")
        XCTAssertTrue(LiveActivityJobs.isMoving(led: true, heard: now.addingTimeInterval(-10), now: now))
        XCTAssertFalse(LiveActivityJobs.isMoving(led: true, heard: now.addingTimeInterval(-60), now: now),
                       "a server gone quiet hands the card back")
        XCTAssertFalse(LiveActivityJobs.isMoving(led: false, heard: now, now: now))
    }

    private static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}

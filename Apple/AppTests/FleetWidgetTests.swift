import SwiftUI
import VPNTunnel
import XCTest
@testable import gryonixNexus

/// The verdicts the four fleet widgets draw
final class FleetWidgetTests: XCTestCase {
    private var appleRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func codeWithoutComments(_ relative: String) throws -> String {
        let text = try String(contentsOf: appleRoot.appendingPathComponent(relative), encoding: .utf8)
        let code = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.isEmpty, "\(relative) was not read")
        return code
    }

    // MARK: - "Nobody looked" is not "nothing is wrong"

    func testAnAbsentReadingIsUnknownRatherThanWell() {
        XCTAssertEqual(FleetPresentation.securityVerdict(nil), .unknown)
        XCTAssertEqual(FleetPresentation.backupsVerdict(nil), .unknown)
        XCTAssertEqual(FleetPresentation.updatesVerdict(nil), .unknown)
        XCTAssertEqual(FleetPresentation.fleetVerdict(FleetSnapshot()), .unknown)
    }

    func testEachVerdictHasItsOwnSymbolAndTint() {
        let all: [FleetPresentation.Verdict] = [.well, .attention, .bad, .unknown]
        XCTAssertEqual(Set(all.map(FleetPresentation.symbol)).count, all.count)
        XCTAssertEqual(Set(all.map { String(describing: FleetPresentation.tint($0)) }).count, all.count)
    }

    // MARK: - Security

    func testInstalledButNotBlockingIsBadNotWell() {
        var summary = FleetSnapshot.SecuritySummary(isPresent: true, engineRunning: true,
                                                    bouncerRunning: true, alertsLast24h: 0,
                                                    localBans: 0, communityBlocklistIPs: 0,
                                                    takenAt: Date())
        XCTAssertEqual(FleetPresentation.securityVerdict(summary), .well)
        summary.bouncerRunning = false
        XCTAssertEqual(FleetPresentation.securityVerdict(summary), .bad)
    }

    func testNeverSetUpIsAttentionRatherThanBad() {
        let absent = FleetSnapshot.SecuritySummary(isPresent: false, engineRunning: false,
                                                   bouncerRunning: false, alertsLast24h: 0,
                                                   localBans: 0, communityBlocklistIPs: 0,
                                                   takenAt: Date())
        XCTAssertEqual(FleetPresentation.securityVerdict(absent), .attention)
    }

    // MARK: - Backups

    func testAScheduleCoveringNoServicesIsNotAnAllClear() {
        let covering = FleetSnapshot.BackupsSummary(isOn: true, everyDays: 1, servicesCovered: 3,
                                                    retention: 7, takenAt: Date())
        XCTAssertEqual(FleetPresentation.backupsVerdict(covering), .well)
        var empty = covering; empty.servicesCovered = 0
        XCTAssertEqual(FleetPresentation.backupsVerdict(empty), .attention)
        var off = covering; off.isOn = false
        XCTAssertEqual(FleetPresentation.backupsVerdict(off), .attention)
    }

    /// The cadence is built from NUMBERS carried in the file
    func testTheCadenceIsWordedFromNumbers() {
        func summary(hours: Int? = nil, days: Int? = nil, on: Bool = true) -> FleetSnapshot.BackupsSummary {
            .init(isOn: on, everyHours: hours, everyDays: days,
                  servicesCovered: 1, retention: 7, takenAt: Date())
        }
        XCTAssertEqual(FleetPresentation.cadence(summary(days: 1)), "Daily")
        XCTAssertEqual(FleetPresentation.cadence(summary(hours: 1)), "Hourly")
        XCTAssertEqual(FleetPresentation.cadence(summary(hours: 6)), "Every 6 hours")
        XCTAssertEqual(FleetPresentation.cadence(summary(days: 3)), "Every 3 days")
        XCTAssertEqual(FleetPresentation.cadence(summary(on: false)), "Off")
        XCTAssertEqual(FleetPresentation.cadence(summary()), "On")
    }

    // MARK: - The fleet

    func testAnUnreachableMachineOutranksAnUnhappyService() {
        var snapshot = FleetSnapshot()
        snapshot.servers = [
            .init(id: UUID(), name: "Fine", services: .init(total: 3, needingAttention: 0, takenAt: Date())),
            .init(id: UUID(), name: "Down", failure: "timed out",
                  services: .init(total: 2, needingAttention: 0, takenAt: Date()))
        ]
        XCTAssertEqual(FleetPresentation.fleetVerdict(snapshot), .bad)

        snapshot.servers[1].failure = nil
        snapshot.servers[1].services?.needingAttention = 1
        XCTAssertEqual(FleetPresentation.fleetVerdict(snapshot), .attention)

        snapshot.servers[1].services?.needingAttention = 0
        XCTAssertEqual(FleetPresentation.fleetVerdict(snapshot), .well)
    }

    // MARK: - What the app refuses to publish

    func testTheBackupScheduleIsNotPublishedBeforeTheServerAnswers() throws {
        let code = try codeWithoutComments("App/Features/Dashboard/DashboardViewModel.swift")
        XCTAssertTrue(code.contains("!autoBackupAnswered ? nil"),
                      "the default schedule can be published as though the server had said it")
    }

    func testAnEmptyUpdateBoardIsNotPublishedAsNothingWaiting() throws {
        let code = try codeWithoutComments("App/Features/Dashboard/DashboardViewModel.swift")
        XCTAssertTrue(code.contains("updateReports.isEmpty ? nil"),
                      "an unanswered update check can be published as an all-clear")
    }

    /// The gallery must show the face that matters
    func testThePlaceholderShowsSomethingWorthLookingAt() {
        let snapshot = FleetSnapshot.placeholder
        XCTAssertGreaterThan(snapshot.totalServices, 0)
        XCTAssertGreaterThan(snapshot.servicesNeedingAttention, 0,
                             "the preview is all-clear, so nobody ever sees the state that matters")
        XCTAssertNotNil(snapshot.servers.first?.security)
        XCTAssertNotNil(snapshot.servers.first?.backups)
        XCTAssertNotNil(snapshot.servers.first?.updates)
    }
}

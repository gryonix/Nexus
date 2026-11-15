import AgentControl
import ServerControl
import XCTest

@testable import gryonixNexus

/// Each island gets its own server's newest job
@MainActor
final class LiveActivityJobsTests: XCTestCase {
    private func server(_ name: String) -> Deployment {
        Deployment(id: UUID(), name: name, topology: .singleHost, domain: "\(name).example",
                   entry: HostEndpoint(host: "203.0.113.7", user: "root"), usesAgent: true)
    }

    func testAJobGoesToTheNewestWaitingRunOfItsServer() async throws {
        let jobs = LiveActivityJobs.shared
        let home = server("home"), office = server("office")
        let older = UUID(), newer = UUID(), elsewhere = UUID()
        jobs.track(older, title: "Backing up", on: home)
        try await Task.sleep(for: .milliseconds(20))
        jobs.track(newer, title: "Updating", on: home)
        jobs.track(elsewhere, title: "Updating", on: office)

        jobs.jobStarted("job-1", on: home.id)
        jobs.jobStarted("job-1", on: home.id)
        jobs.jobStarted("job-2", on: home.id)
        jobs.jobStarted("job-3", on: office.id)

        XCTAssertEqual(jobs.jobID(of: newer), "job-1")
        XCTAssertEqual(jobs.jobID(of: older), "job-2")
        XCTAssertEqual(jobs.jobID(of: elsewhere), "job-3")
        [older, newer, elsewhere].forEach(jobs.forget)
    }

    func testAServerWithoutTheAgentIsNotTracked() {
        var plain = server("plain")
        plain.usesAgent = false
        let run = UUID()
        LiveActivityJobs.shared.track(run, title: "Updating", on: plain)
        LiveActivityJobs.shared.jobStarted("job-9", on: plain.id)
        XCTAssertNil(LiveActivityJobs.shared.jobID(of: run))
    }

    func testAPairedJobIsJournaledAndTheAppStillLeadsUntilTheServerAgrees() {
        let jobs = LiveActivityJobs.shared
        let home = server("journal")
        let run = UUID()
        jobs.track(run, title: "Updating journal", on: home)
        jobs.jobStarted("job-journal", on: home.id)
        XCTAssertFalse(jobs.isServerLed(run))
        let last = IslandJournal.shared.entries.last
        XCTAssertEqual(last?.run, "Updating journal")
        XCTAssertTrue(last?.text.contains("job-jour") == true)
        jobs.forget(run)
    }

    func testTheJournalKeepsOnlyTheNewestEntries() {
        let journal = IslandJournal.shared
        for index in 0...IslandJournal.limit { journal.note("entry \(index)") }
        XCTAssertEqual(journal.entries.count, IslandJournal.limit)
        XCTAssertEqual(journal.entries.last?.text, "entry \(IslandJournal.limit)")
        XCTAssertTrue(IslandJournal.line(journal.entries.last!).hasSuffix("entry \(IslandJournal.limit)"))
        journal.clear()
    }

    func testASystemUpdateIsHandedOverUnderItsOwnJobAndNeverPairedWithAnother() {
        let jobs = LiveActivityJobs.shared
        let home = server("updates")
        let run = UUID()
        jobs.track(run, title: "Updating the system", on: home, jobID: SystemUpdateModel.islandJob)
        jobs.jobStarted("job-other", on: home.id)
        XCTAssertEqual(jobs.jobID(of: run), "system-update")
        jobs.forget(run)
    }

    func testARunOnTheServersCardIsLedByTheServerAndHandsNothingOver() {
        let jobs = LiveActivityJobs.shared
        let home = server("server-card")
        let run = UUID()
        jobs.track(run, title: "Backing up", on: home, jobID: "job-server-card")
        XCTAssertFalse(jobs.isServerLed(run))
        jobs.serverMoves(run)
        XCTAssertTrue(jobs.isServerLed(run))
        jobs.tokenArrived("old-own-card", for: run)
        XCTAssertTrue(jobs.isServerLed(run))
        XCTAssertFalse(IslandJournal.shared.entries.contains { $0.text.contains("did not take the card") && $0.run == "Backing up" })
        jobs.forget(run)
    }

    func testEachJobKindMatchesTheKindTheAgentNamesToTheRelay() {
        let expected: [AgentJobKind: OperationKind] = [
            .install: .install, .repair: .install, .reinstall: .install,
            .update: .update, .containerUpdate: .update, .agentUpdate: .update,
            .backup: .backup, .containerBackup: .backup, .restore: .restore, .move: .move,
            .uninstall: .removal, .containerRemoval: .removal,
            .serviceControl: .other, .containerControl: .other, .modelPull: .other,
            .securityControl: .other, .unknown: .other,
        ]
        XCTAssertEqual(Set(expected.keys), Set(AgentJobKind.allCases))
        for (job, kind) in expected { XCTAssertEqual(LiveActivityJobs.kind(of: job), kind, "\(job)") }
    }

    func testTheSettingsSwitchesReachCardsTheAppOpens() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LiveActivityJobsTests.switches"))
        defaults.removePersistentDomain(forName: "LiveActivityJobsTests.switches")
        let settings = LiveActivitySettings(defaults: defaults)
        XCTAssertTrue(settings.shows(nil))
        settings.hiddenOperationKinds = [.backup]
        XCTAssertFalse(settings.shows(.backup))
        XCTAssertTrue(settings.shows(.update))
        XCTAssertTrue(settings.shows(nil), "a run of unknown kind follows the main switch")
        settings.showsOperations = false
        XCTAssertFalse(settings.shows(nil))
        XCTAssertFalse(settings.shows(.update))
        defaults.removePersistentDomain(forName: "LiveActivityJobsTests.switches")
    }

    func testTheLaunchSweepLeavesTheServersCardsToTheServer() {
        XCTAssertTrue(OperationActivities.isOrphan(ownedHere: false, followedJob: nil, serverJob: nil))
        XCTAssertFalse(OperationActivities.isOrphan(ownedHere: false, followedJob: nil, serverJob: "job-1"),
                       "a card the server opened is ended by the server, not at launch")
        XCTAssertFalse(OperationActivities.isOrphan(ownedHere: false, followedJob: "job-1", serverJob: nil))
        XCTAssertFalse(OperationActivities.isOrphan(ownedHere: true, followedJob: nil, serverJob: nil))
    }

    func testOnlyAStaleOrEndedJobCardIsTakenOff() {
        let now = Date()
        let later = now.addingTimeInterval(60), earlier = now.addingTimeInterval(-60)
        XCTAssertFalse(OperationActivities.isAbandoned(followedJob: nil, serverJob: "job-1", isActive: true,
                                                       staleDate: later, now: now))
        XCTAssertTrue(OperationActivities.isAbandoned(followedJob: nil, serverJob: "job-1", isActive: true,
                                                      staleDate: earlier, now: now))
        XCTAssertTrue(OperationActivities.isAbandoned(followedJob: "job-1", serverJob: nil, isActive: false,
                                                      staleDate: later, now: now))
        XCTAssertFalse(OperationActivities.isAbandoned(followedJob: nil, serverJob: nil, isActive: false,
                                                       staleDate: earlier, now: now),
                       "a card of no job is the launch sweep's, not this one's")
    }
}

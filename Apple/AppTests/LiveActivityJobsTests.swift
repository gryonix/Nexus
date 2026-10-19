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
}

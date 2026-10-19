import XCTest
@testable import VPNTunnel

final class TunnelSessionLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func log(capacity: Int = TunnelSessionLog.capacity) -> TunnelSessionLog {
        TunnelSessionLog(fileURL: directory.appendingPathComponent("sessions.json"),
                         capacity: capacity)
    }

    private func session(startedAt: Date = Date(), simulated: Bool = true) -> TunnelSession {
        TunnelSession(profileID: UUID(), serverName: "Home", protocolName: "WireGuard",
                      deviceName: "iPhone", startedAt: startedAt, wasSimulated: simulated)
    }

    func testAnOpenSessionIsTheRunningOne() {
        let log = log()
        let started = log.begin(session())
        XCTAssertEqual(log.running()?.id, started.id)

        log.end(id: started.id, statistics: TunnelStatistics(received: 10, sent: 5))
        XCTAssertNil(log.running())
        XCTAssertEqual(log.sessions().first?.statistics.received, 10)
    }

    func testAnInterruptedSessionIsClosedByTheNextConnectionRatherThanLeftOpen() {
        let log = log()
        let abandoned = log.begin(session(startedAt: Date(timeIntervalSince1970: 1_000)))
        let fresh = log.begin(session(startedAt: Date(timeIntervalSince1970: 2_000)))

        XCTAssertEqual(log.running()?.id, fresh.id, "exactly one session may be open")
        let closed = log.sessions().first { $0.id == abandoned.id }
        XCTAssertNotNil(closed?.endedAt)
        XCTAssertNotNil(closed?.failureReason, "an interrupted session must say it was interrupted")
    }

    func testAProperlyClosedSessionIsNotRewrittenByTheNextConnection() {
        let log = log()
        let first = log.begin(session(startedAt: Date(timeIntervalSince1970: 1_000)))
        let ended = Date(timeIntervalSince1970: 1_500)
        log.end(id: first.id, at: ended, statistics: TunnelStatistics(received: 7, sent: 3))
        log.begin(session(startedAt: Date(timeIntervalSince1970: 2_000)))

        let stored = log.sessions().first { $0.id == first.id }
        XCTAssertEqual(stored?.endedAt, ended)
        XCTAssertNil(stored?.failureReason)
        XCTAssertEqual(stored?.statistics.received, 7)
    }

    func testClosingASessionTwiceIsIgnored() {
        let log = log()
        let started = log.begin(session())
        log.end(id: started.id, at: Date(timeIntervalSince1970: 100),
                statistics: TunnelStatistics(received: 1, sent: 1))
        log.end(id: started.id, at: Date(timeIntervalSince1970: 999),
                statistics: TunnelStatistics(received: 5, sent: 5))

        let stored = log.sessions().first
        XCTAssertEqual(stored?.endedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(stored?.statistics.received, 1)
    }

    func testLiveCountersOnlyReachTheSessionThatIsStillOpen() {
        let log = log()
        let started = log.begin(session())
        log.update(id: started.id, statistics: TunnelStatistics(received: 42, sent: 7))
        XCTAssertEqual(log.running()?.statistics.received, 42)

        log.end(id: started.id, statistics: TunnelStatistics(received: 42, sent: 7))
        log.update(id: started.id, statistics: TunnelStatistics(received: 999, sent: 999))
        XCTAssertEqual(log.sessions().first?.statistics.received, 42,
                       "a tick landing after the session ended must not resurrect it")
    }

    func testTheOldestSessionsAreDroppedAtCapacity() {
        let log = log(capacity: 3)
        for index in 0..<5 {
            let started = log.begin(session(startedAt: Date(timeIntervalSince1970: TimeInterval(index))))
            log.end(id: started.id, statistics: .zero)
        }
        let kept = log.sessions().map(\.startedAt.timeIntervalSince1970).sorted()
        XCTAssertEqual(kept, [2, 3, 4])
    }

    func testTotalsCoverTheWindowAndCountTheSessionStillRunning() {
        let log = log()
        let old = log.begin(session(startedAt: Date(timeIntervalSince1970: 0)))
        log.end(id: old.id, at: Date(timeIntervalSince1970: 10),
                statistics: TunnelStatistics(received: 100, sent: 50))
        let running = log.begin(session())
        log.update(id: running.id, statistics: TunnelStatistics(received: 5, sent: 2))

        let month = log.total(since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(month.received, 5, "the ancient session is outside the window")
        XCTAssertEqual(month.sent, 2)

        let everything = log.total(since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(everything.received, 105)
    }

    func testASessionRemembersWhetherItWasReal() {
        let log = log()
        log.begin(session(simulated: true))
        XCTAssertEqual(log.sessions().first?.wasSimulated, true)
    }
}

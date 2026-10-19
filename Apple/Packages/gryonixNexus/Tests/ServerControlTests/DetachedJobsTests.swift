import XCTest
@testable import ServerControl

final class DetachedJobsTests: XCTestCase {
    func testTheLaunchDetachesAndLeavesASentinel() {
        let command = DetachedJobs.startCommand("/opt/gryonixnexus-update-ctl.sh run nextcloud",
                                                jobID: "update-nextcloud-1000")
        XCTAssertTrue(command.contains("setsid"), "without this sshd hangs the run up with the channel")
        XCTAssertTrue(command.contains(DetachedJobs.exitMarker),
                      "without the sentinel, 'ended' cannot be told from 'disconnected'")
        XCTAssertTrue(command.contains("umask 077"), "the log is as private as what it narrates")
        let create = command.range(of: ": > ")
        let launch = command.range(of: "$DETACH sh -c")
        XCTAssertNotNil(create)
        XCTAssertNotNil(launch)
        XCTAssertTrue(create!.lowerBound < launch!.lowerBound, "the log must exist before the run does")
    }

    func testTheFollowerResumesAndTerminates() {
        let command = DetachedJobs.followCommand(jobID: "backup-immich-2000", fromLine: 41)
        XCTAssertTrue(command.contains("n=41"), "a client that saw 40 lines asks for the 41st")
        XCTAssertTrue(command.contains("exit 0"), "it has to leave when the sentinel is the last line")
        XCTAssertFalse(command.contains("tail -f"), "tail -f deadlocks here — see SetupInstaller")
    }

    func testTheListingTellsRunningFromFinished() {
        let jobs = DetachedJobs.parseList("""
        update-nextcloud-1700 0
        backup-immich-1800 -
        uninstall-pihole-1600 3
        """)
        XCTAssertEqual(jobs.map(\.id), ["backup-immich-1800", "update-nextcloud-1700", "uninstall-pihole-1600"],
                       "newest first")
        XCTAssertEqual(jobs.first?.kind, .backup)
        XCTAssertEqual(jobs.first?.subject, "immich")
        XCTAssertTrue(jobs.first!.isRunning, "no sentinel yet means it is still going")
        XCTAssertFalse(jobs[1].isRunning)
        XCTAssertEqual(jobs[1].exitCode, 0)
        XCTAssertEqual(jobs[2].exitCode, 3, "a failure keeps its code, which is what says what happened")
    }

    func testTheLaunchIsTheExactShellBothAppsSend() {
        let expected = #"umask 077; mkdir -p '.gryonixnexus/jobs' || exit 1; exec 9> '.gryonixnexus/jobs/x.lock'; flock -n 9 || { echo 'An operation is already running for this service. Wait for it to finish.' >&2; exit 75; }; : > '.gryonixnexus/jobs/update-x-7.log' || exit 1; command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH=; $DETACH sh -c 'sudo /opt/x.sh run >> '\''.gryonixnexus/jobs/update-x-7.log'\'' 2>&1; echo "GRYONIXNEXUS_JOB_EXIT:$?" >> '\''.gryonixnexus/jobs/update-x-7.log'\''' </dev/null >/dev/null 2>&1 & echo 'update-x-7'"#
        XCTAssertEqual(DetachedJobs.startCommand("sudo /opt/x.sh run", jobID: "update-x-7"), expected)
    }
    func testASubjectWithDashesComesBackWhole() {
        let id = DetachedJobs.jobID(kind: .backup, subject: "adguard-home", at: 1234)
        XCTAssertEqual(id, "backup-adguard-home-1234")
        let jobs = DetachedJobs.parseList("\(id) -")
        XCTAssertEqual(jobs.first?.subject, "adguard-home")
        XCTAssertEqual(jobs.first?.kind, .backup)
        XCTAssertEqual(jobs.first?.startedUnix, 1234)
    }

    func testALineThatIsNotAJobIsSkipped() {
        XCTAssertTrue(DetachedJobs.parseList("notes.txt 0\nrubbish\n").isEmpty)
        XCTAssertTrue(DetachedJobs.parseList("install-x-1 0").isEmpty,
                      "a kind this app does not know is not a kind it may invent")
    }

    func testAnUnsafeSubjectIsReducedBeforeItReachesTheShell() {
        let id = DetachedJobs.jobID(kind: .update, subject: "a b;rm -rf /", at: 7)
        XCTAssertFalse(id.contains(";"))
        XCTAssertFalse(id.contains(" "))
        XCTAssertFalse(id.contains("/"))
    }

    func testADroppedStreamIsReattachedFromTheLastLine() async throws {
        let fake = FakeSSHCommandRunner()
        fake.stub("", stdout: "one\ntwo\n")
        fake.stub("", stdout: "three\n\(DetachedJobs.exitMarker)0\n")
        let seen = LockedLines()
        try await DetachedJobs.follow(jobID: "backup-svc-1", from: 1, on: .vps, runner: fake,
                                      runTimeout: .seconds(5), retryDelay: .milliseconds(1)) { seen.add($0) }
        XCTAssertEqual(seen.lines, ["one\n", "two\n", "three\n"])
        let follows = fake.calls.filter { $0.kind == .stream }.map(\.command)
        XCTAssertEqual(follows.count, 2)
        XCTAssertTrue(follows[1].contains("n=3"), "the second attach must start after the lines already shown")
    }

    func testAJobThatKeepsDroppingEventuallyFailsWithoutAnExitCode() async {
        let fake = FakeSSHCommandRunner()
        for _ in 0..<3 { fake.stub("", stdout: "") }
        do {
            try await DetachedJobs.follow(jobID: "backup-svc-1", from: 1, on: .vps, runner: fake,
                                          runTimeout: .seconds(5), reattaches: 2,
                                          retryDelay: .milliseconds(1)) { _ in }
            XCTFail("a job with no exit marker must not read as done")
        } catch let error as ServerControlError {
            guard case .commandFailed(_, let code, _) = error else { return XCTFail("\(error)") }
            XCTAssertNil(code)
        } catch {
            XCTFail("\(error)")
        }
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ line: String) { lock.lock(); stored.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}

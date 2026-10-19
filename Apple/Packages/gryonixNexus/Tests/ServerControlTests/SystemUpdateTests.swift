@testable import ServerControl
import XCTest

final class SystemUpdateTests: XCTestCase {
    /// Real output of the updater on a server
    private let finished = """
    state=idle
    exit=0
    finished=1790629350
    reboot=no
    system=on
    apps=off
    log:
    Reading state information...
    0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
    GRYONIXNEXUS_SYSTEM_EXIT:0

    """

    private let fresh = "state=idle\nexit=\nfinished=0\nreboot=no\nsystem=off\napps=off\nlog:\n"

    func testAFinishedRunReadsItsCodeLogAndSwitches() throws {
        let status = try XCTUnwrap(SystemUpdateStatus.parse(finished))
        XCTAssertFalse(status.isRunning)
        XCTAssertEqual(status.exitCode, 0)
        XCTAssertEqual(status.finished, Date(timeIntervalSince1970: 1_790_629_350))
        XCTAssertTrue(status.systemAtStart)
        XCTAssertFalse(status.appsAtStart)
        XCTAssertEqual(status.log.last, "0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.")
    }

    func testAHostThatNeverRanHasNoCodeOrDate() throws {
        let status = try XCTUnwrap(SystemUpdateStatus.parse(fresh))
        XCTAssertNil(status.exitCode)
        XCTAssertNil(status.finished)
        XCTAssertTrue(status.log.isEmpty)
        XCTAssertNil(SystemUpdateStatus.parse("sudo: a password is required\n"))
    }

    func testSwapIsReadAndSet() throws {
        let status = try XCTUnwrap(SystemUpdateStatus.parse("state=idle\nswap=2147479552\nswapfile=2147483648\nlog:\n"))
        XCTAssertEqual(status.swapBytes, 2_147_479_552)
        XCTAssertEqual(status.swapFileBytes, 2_147_483_648)
        XCTAssertEqual(SystemUpdate.swapCommand(sizeGB: 4), "sudo -n /opt/gryonixnexus-system-ctl.sh swap 4")
        XCTAssertEqual(SystemUpdate.swapCommand(sizeGB: nil), "sudo -n /opt/gryonixnexus-system-ctl.sh swap off")
    }

    func testCommandsNameTheScriptAndItsArguments() {
        XCTAssertEqual(SystemUpdate.atStartCommand(.apps, on: true),
                       "sudo -n /opt/gryonixnexus-system-ctl.sh at-start apps on")
        XCTAssertTrue(SystemUpdate.isMissing(ExecResult(exitCode: 1, stdout: "", stderr: "sudo: a password is required\n")))
        XCTAssertFalse(SystemUpdate.isMissing(ExecResult(exitCode: 1, stdout: "", stderr: "E: dpkg was interrupted")))
    }

    func testShutdownSwitchesShowOnlyWhenTheUpdaterKnowsThem() throws {
        let old = try XCTUnwrap(SystemUpdateStatus.parse(fresh))
        XCTAssertFalse(old.offersAtStop)
        let new = try XCTUnwrap(SystemUpdateStatus.parse("state=idle\nsystem_stop=on\napps_stop=off\nlog:\n"))
        XCTAssertTrue(new.offersAtStop)
        XCTAssertTrue(new.systemAtStop)
        XCTAssertFalse(new.appsAtStop)
        XCTAssertEqual(SystemUpdate.atStopCommand(.system, on: false),
                       "sudo -n /opt/gryonixnexus-system-ctl.sh at-stop system off")
    }

    func testTheScheduleIsReadAndSent() throws {
        XCTAssertNil(try XCTUnwrap(SystemUpdateStatus.parse(fresh)).schedule, "an older updater has no timer")
        let off = try XCTUnwrap(SystemUpdateStatus.parse("state=idle\nschedule=off\nlog:\n"))
        XCTAssertEqual(off.schedule, .off)
        let weekly = try XCTUnwrap(SystemUpdateStatus.parse("state=idle\nschedule=every:7d@03:30\nlog:\n"))
        XCTAssertEqual(weekly.schedule, .days(count: 7, hour: 3, minute: 30))
        XCTAssertEqual(SystemUpdate.scheduleCommand(.days(count: 7, hour: 3, minute: 30)),
                       "sudo -n /opt/gryonixnexus-system-ctl.sh schedule every:7d@03:30")
        XCTAssertEqual(SystemUpdate.scheduleCommand(.off), "sudo -n /opt/gryonixnexus-system-ctl.sh schedule off")
    }

    func testSudoRefusingTheGrantReadsAsAMissingUpdater() {
        let refusal = "sudo: I'm sorry server-user. I'm afraid I can't do that\n"
        XCTAssertTrue(SystemUpdate.isMissing(ExecResult(exitCode: 1, stdout: "", stderr: refusal)))
    }
}

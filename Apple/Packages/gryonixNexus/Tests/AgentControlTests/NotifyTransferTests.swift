import AgentClient
import XCTest
@testable import AgentControl

final class NotifyTransferTests: XCTestCase {
    private func request() -> Gryonixnexusd_V1_SetNotifySettingsRequest {
        var request = Gryonixnexusd_V1_SetNotifySettingsRequest()
        request.channel = .ntfy
        request.ntfyURL = "https://ntfy.example.net"
        request.ntfyTopic = "gnx-abc"
        request.customChecks = true
        request.language = "de"
        request.checks.raid = true
        request.checks.services = false
        request.checks.diskSpacePercent = 80
        request.checks.sshLogins = true
        return request
    }

    func testAFileCarriesTheChannelAndTheChecksAndComesBackTheSame() throws {
        let file = try NotifyTransfer(request: request()).encoded()
        let read = try NotifyTransfer.decode(file)
        var draft = Gryonixnexusd_V1_SetNotifySettingsRequest()
        draft.language = "uk"
        let applied = read.applied(to: draft)
        XCTAssertEqual(applied.channel, .ntfy)
        XCTAssertEqual(applied.ntfyTopic, "gnx-abc")
        XCTAssertEqual(applied.ntfyURL, "https://ntfy.example.net")
        XCTAssertTrue(applied.customChecks)
        XCTAssertFalse(applied.checks.services)
        XCTAssertEqual(applied.checks.diskSpacePercent, 80)
        XCTAssertEqual(applied.language, "uk", "the language belongs to this device")
    }

    func testDefaultsFollowingServersKeepTheirOwnChecks() throws {
        var plain = request()
        plain.customChecks = false
        let read = try NotifyTransfer.decode(NotifyTransfer(request: plain).encoded())
        var draft = Gryonixnexusd_V1_SetNotifySettingsRequest()
        draft.checks.services = true
        let applied = read.applied(to: draft)
        XCTAssertFalse(applied.customChecks)
        XCTAssertTrue(applied.checks.services)
    }

    func testOtherFilesAreRefused() {
        XCTAssertThrowsError(try NotifyTransfer.decode(Data("{}".utf8))) {
            XCTAssertEqual($0 as? NotifyTransfer.Failure, .notAPushFile)
        }
        XCTAssertThrowsError(try NotifyTransfer.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? NotifyTransfer.Failure, .notAPushFile)
        }
        var odd = NotifyTransfer(request: request())
        odd.channel = "carrier-pigeon"
        XCTAssertThrowsError(try NotifyTransfer.decode(odd.encoded())) {
            XCTAssertEqual($0 as? NotifyTransfer.Failure, .unknownChannel)
        }
        var future = NotifyTransfer(request: request())
        future.version = 99
        XCTAssertThrowsError(try NotifyTransfer.decode(future.encoded())) {
            XCTAssertEqual($0 as? NotifyTransfer.Failure, .newerVersion)
        }
    }
}

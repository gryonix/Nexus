import AgentClient
import ServerControl
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
@MainActor
final class SystemSettingsModelTests: XCTestCase {
    private var deployment: Deployment { DemoServer.deployment() }

    func testTheDemoServerReportsAndChangesItsSettings() async throws {
        let demo = deployment
        let model = SystemSettingsModel { _ in try XCTUnwrap(DemoAgent.client(for: demo)) }
        await model.load([.vps])
        let first = try XCTUnwrap(model.settings[.vps])
        XCTAssertFalse(first.timeZone.isEmpty)
        XCTAssertTrue(first.timeZones.contains("UTC"))
        await model.setTimeZone("UTC", host: .vps)
        await model.setHostName("draco", host: .vps)
        await model.setTimeSync(false, host: .vps)
        let after = try XCTUnwrap(model.settings[.vps])
        XCTAssertEqual(after.timeZone, "UTC")
        XCTAssertEqual(after.hostName, "draco")
        XCTAssertFalse(after.ntpEnabled)
    }

    func testAnOlderAgentLeavesNoRows() async {
        let model = SystemSettingsModel { _ in throw AgentError.rpc(code: "not_found", message: "unknown method") }
        await model.load([.vps])
        XCTAssertNil(model.settings[.vps])
        XCTAssertNil(model.errors[.vps])
    }
}

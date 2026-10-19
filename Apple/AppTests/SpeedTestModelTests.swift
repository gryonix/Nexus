import ServerControl
import XCTest
@testable import gryonixNexus

@MainActor
final class SpeedTestModelTests: XCTestCase {
    /// A demo server's internet test leaves a record behind
    func testTheDemoInternetTestRecordsItsNumbers() async throws {
        setenv("GRYONIXNEXUS_DEMO_SERVERS", "1", 1)
        defer { unsetenv("GRYONIXNEXUS_DEMO_SERVERS") }
        let demo = try XCTUnwrap(DemoDeployments.fromEnvironment()?.first)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "speed-\(UUID())"))
        let model = SpeedTestViewModel(target: SpeedTestTarget(deployment: demo, host: .vps),
                                       history: SpeedTestHistory(defaults: defaults))
        await model.testInternet()
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.latest(SpeedTestViewModel.internet)?.internet)
    }
}

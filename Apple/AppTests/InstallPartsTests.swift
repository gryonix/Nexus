import XCTest
@testable import gryonixNexus

final class InstallPartsTests: XCTestCase {
    func testWithoutTheAgentTheScriptIsTheWholeBar() {
        XCTAssertEqual(InstallParts().fraction(script: 0.5), 0.5)
    }

    func testTheBarNeverGoesBackBetweenParts() {
        var parts = InstallParts(throughAgent: true)
        let endOfScript = parts.fraction(script: 1)
        parts.scriptDone = true
        XCTAssertEqual(parts.fraction(script: 0), endOfScript, "a new step count must not reset the bar")
        parts.agentBuild.line("   Compiling serde v1.0.229")
        XCTAssertGreaterThan(parts.fraction(script: 0), endOfScript)
        parts.agentDone = true
        parts.servicesTotal = 2
        parts.servicesDone = 1
        XCTAssertEqual(parts.fraction(script: 0), 0.85, accuracy: 0.001)
        parts.servicesDone = 2
        XCTAssertEqual(parts.fraction(script: 0), 1, accuracy: 0.001)
    }

    func testTheDirectPathFillsOnlyTheServicesShare() {
        var parts = InstallParts(throughAgent: true)
        parts.scriptDone = true
        parts.directServices = true
        parts.directStep = 0
        XCTAssertEqual(parts.fraction(script: 0), 0.7, accuracy: 0.001)
        parts.directStep = 0.5
        XCTAssertEqual(parts.fraction(script: 0), 0.85, accuracy: 0.001)
    }
}

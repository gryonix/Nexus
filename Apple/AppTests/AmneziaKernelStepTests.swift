import XCTest
@testable import gryonixNexus

/// The step line reads the agent's "3/4"
final class AmneziaKernelStepTests: XCTestCase {
    func testACountBecomesAStep() {
        let step = AmneziaKernelSection.step("3/4")
        XCTAssertEqual(step?.done, 3)
        XCTAssertEqual(step?.all, 4)
    }

    func testAnythingElseShowsNoStep() {
        for note in ["", "4", "0/4", "5/4", "a/b", "1/2/3", "less than 1 GB free on the disk"] {
            XCTAssertNil(AmneziaKernelSection.step(note), note)
        }
    }
}

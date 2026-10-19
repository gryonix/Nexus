import AgentClient
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
final class DeviceListTests: XCTestCase {
    func testTheSameDeviceListedTwiceShowsOnce() {
        var first = Gryonixnexusd_V1_Device()
        first.id = "dev-1"
        first.label = "iPhone"
        var again = first
        again.label = "Mac"
        var other = Gryonixnexusd_V1_Device()
        other.id = "dev-2"

        XCTAssertEqual([first, again, other].uniquedByID().map(\.id), ["dev-1", "dev-2"])
        XCTAssertEqual([first, again].uniquedByID().first?.label, "iPhone")
    }
}

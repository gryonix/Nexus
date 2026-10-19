import XCTest
@testable import gryonixNexusCore

final class WakeOnLANDeviceTargetsTests: XCTestCase {
    func testTheNetworkEveryoneAndTheMachine() {
        XCTAssertEqual(WakeOnLAN.deviceTargets(broadcast: "192.168.178.255", host: "192.168.178.111"),
                       ["192.168.178.255", "255.255.255.255", "192.168.178.111"])
    }

    func testANameIsNotSentTo() {
        XCTAssertEqual(WakeOnLAN.deviceTargets(broadcast: "192.168.178.255", host: "draco.local"),
                       ["192.168.178.255", "255.255.255.255"])
        XCTAssertEqual(WakeOnLAN.deviceTargets(broadcast: WakeOnLAN.limitedBroadcast, host: nil),
                       ["255.255.255.255"])
    }
}

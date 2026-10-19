import XCTest

@testable import gryonixNexusCore

final class WakeOnLANNetworkTests: XCTestCase {
    private let home = WakeOnLAN.DeviceAddress(address: "192.168.178.23", netmask: "255.255.255.0")
    private let cellular = WakeOnLAN.DeviceAddress(address: "10.132.7.9", netmask: "255.255.255.255")
    private let tunnel = WakeOnLAN.DeviceAddress(address: "10.66.66.2", netmask: "255.255.255.255")

    func testAPhoneOnTheHomeWiFiSharesTheMachinesNetwork() {
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [home], machine: "192.168.178.100", broadcast: nil), true)
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [cellular, home], machine: "192.168.178.100", broadcast: nil), true)
    }

    func testAPhoneOnMobileDataOrAnotherWiFiDoesNot() {
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [cellular], machine: "192.168.178.100", broadcast: nil), false)
        let cafe = WakeOnLAN.DeviceAddress(address: "192.168.1.40", netmask: "255.255.255.0")
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [cafe, tunnel], machine: "192.168.178.100", broadcast: nil), false)
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [], machine: "192.168.178.100", broadcast: nil), false)
    }

    func testTheStoredBroadcastAnswersWhenOnlyANameIsKnown() {
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [home], machine: nil, broadcast: "192.168.178.255"), true)
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [cellular], machine: nil, broadcast: "192.168.178.255"), false)
        let wide = WakeOnLAN.DeviceAddress(address: "10.0.4.7", netmask: "255.255.0.0")
        XCTAssertEqual(WakeOnLAN.sharesNetwork(device: [wide], machine: nil, broadcast: "10.0.255.255"), true)
    }

    func testNothingKnownAboutTheMachineIsNoAnswer() {
        XCTAssertNil(WakeOnLAN.sharesNetwork(device: [home], machine: nil, broadcast: nil))
        XCTAssertNil(WakeOnLAN.sharesNetwork(device: [home], machine: "draco.local", broadcast: "255.255.255.255"))
    }
}

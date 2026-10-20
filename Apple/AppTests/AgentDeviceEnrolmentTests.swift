import AgentClient
import XCTest

@testable import gryonixNexus

/// When this device puts itself into a server's paired-device registry
@available(macOS 15.0, *)
final class AgentDeviceEnrolmentTests: XCTestCase {
    private func device(key: String, label: String) -> Gryonixnexusd_V1_Device {
        var device = Gryonixnexusd_V1_Device()
        device.id = "dev-" + label
        device.publicKey = key
        device.label = label
        return device
    }

    func testAnUnregisteredDeviceEnrols() {
        let others = [device(key: "ssh-ed25519 AAAAsomeone-else", label: "Mac")]
        XCTAssertTrue(AgentDeviceEnrolment.needsEnrolment(devices: others,
                                                          thisDevicePublicKey: "ssh-ed25519 AAAAme"))
        XCTAssertTrue(AgentDeviceEnrolment.needsEnrolment(devices: [],
                                                          thisDevicePublicKey: "ssh-ed25519 AAAAme"))
    }

    func testADeviceAlreadyInTheListDoesNotPairAgain() {
        let key = "ssh-ed25519 AAAAme"
        let listed = [device(key: "ssh-ed25519 AAAAsomeone-else", label: "Mac"),
                      device(key: key, label: "iPhone")]
        XCTAssertFalse(AgentDeviceEnrolment.needsEnrolment(devices: listed,
                                                           thisDevicePublicKey: key))
    }

    func testAnUnreadableKeyEnrolsNothing() {
        XCTAssertFalse(AgentDeviceEnrolment.needsEnrolment(devices: [], thisDevicePublicKey: nil))
        XCTAssertFalse(AgentDeviceEnrolment.needsEnrolment(devices: [], thisDevicePublicKey: ""))
    }

    #if canImport(UIKit)
    func testTheDeviceIsNamedForItsModelNotJustItsKind() {
        XCTAssertEqual(DeviceModelName.names["iPhone19,4"], "iPhone Duo")
        XCTAssertEqual(DeviceModelName.names["iPhone18,1"], "iPhone 17 Pro")
        XCTAssertNotEqual(AgentDeviceEnrolment.deviceLabel, "iPhone",
                          "every configuration was called iPhone and could not be told apart")
    }
    #endif
}

import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// When the Zigbee stick may be picked instead of typed
@MainActor
final class SerialDevicePickerTests: XCTestCase {
    private func server(usesAgent: Bool) -> Deployment {
        Deployment(name: "home",
                   topology: .vpsRelayWithHomeBackend,
                   domain: "example.net",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.homeAssistant],
                   usesAgent: usesAgent)
    }

    /// A fresh install has no machine to ask yet
    func testTheConfiguratorWithNoServerBehindItOffersNoPicker() {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        XCTAssertFalse(model.canListSerialDevices)
    }

    /// The listing is an agent verb; SSH-only cannot answer
    func testAServerWithoutAnAgentOffersNoPicker() {
        let model = ServiceConfigViewModel(topology: .vpsRelayWithHomeBackend,
                                           existingServer: server(usesAgent: false))
        XCTAssertFalse(model.canListSerialDevices)
    }

    func testAServerWithAnAgentOffersThePicker() {
        let model = ServiceConfigViewModel(topology: .vpsRelayWithHomeBackend,
                                           existingServer: server(usesAgent: true))
        XCTAssertTrue(model.canListSerialDevices)
        XCTAssertEqual(model.serialListing, .idle)
    }

    /// Reading the list leaves a typed path alone
    func testLoadingTheListLeavesTheTypedPathAlone() async {
        let model = ServiceConfigViewModel(topology: .vpsRelayWithHomeBackend,
                                           existingServer: server(usesAgent: false))
        model.homeAssistantUSBDevice = "/dev/serial/by-id/usb-Acme-if00-port0"
        await model.loadSerialDevices()
        XCTAssertEqual(model.homeAssistantUSBDevice, "/dev/serial/by-id/usb-Acme-if00-port0")
        XCTAssertEqual(model.serialListing, .idle)
    }

    /// An empty list means two different things
    func testAnEmptyListingKeepsTheDifferenceBetweenNoStickAndNoUSBAtAll() {
        XCTAssertNotEqual(SerialListing.loaded([], directoryPresent: true),
                          SerialListing.loaded([], directoryPresent: false))
    }

    /// The picked row stores the by-id path
    func testTheOptionStoresTheStablePathAndNotTheCurrentNode() {
        let option = SerialDeviceOption(path: "/dev/serial/by-id/usb-Acme-if00-port0",
                                        target: "/dev/ttyUSB0",
                                        label: "Acme")
        XCTAssertEqual(option.id, option.path)
        XCTAssertNotEqual(option.id, option.target)
    }
}

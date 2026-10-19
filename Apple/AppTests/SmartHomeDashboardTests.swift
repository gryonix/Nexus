import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// The hub and its add-ons, as the dashboard shows them
@MainActor
final class SmartHomeDashboardTests: XCTestCase {
    private func deployment() -> Deployment {
        Deployment(name: "home",
                   topology: .vpsRelayWithHomeBackend,
                   domain: "example.net",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.homeAssistant, .mosquitto, .zigbee2MQTT],
                   serviceSettings: ServiceSettings(homeAssistantUSBDevice: "/dev/ttyACM0"))
    }

    func testTheHubAndTheBridgeAreListedAsSites() {
        let model = DashboardViewModel(deployment: deployment())
        let hosts = model.webSites.map(\.host)
        XCTAssertTrue(hosts.contains("home.example.net"), "\(hosts)")
        XCTAssertTrue(hosts.contains("zigbee.example.net"), "\(hosts)")
    }

    /// A broker speaks MQTT and has no address
    func testTheBrokerIsNotASite() {
        let model = DashboardViewModel(deployment: deployment())
        for site in model.webSites {
            XCTAssertNotEqual(site.host, "mosquitto.example.net", "\(site.host)")
        }
        XCTAssertFalse(model.sitesNeedDomain)
    }

    /// All three can be powered, logged, updated, archived
    func testEachSmartHomeServiceCarriesTheFullSetOfActions() {
        let context = deployment().serviceContext
        for id in [ServiceID.homeAssistant, .mosquitto, .zigbee2MQTT] {
            let service = ServiceRegistry.service(id)
            XCTAssertNotNil(service, id.rawValue)
            guard let service else { continue }
            let actions = service.actions(context)
            XCTAssertNotNil(actions.restart, id.rawValue)
            XCTAssertNotNil(actions.logs, id.rawValue)
            XCTAssertNotNil(actions.backup, id.rawValue)
            XCTAssertNotNil(actions.restore, id.rawValue)
            XCTAssertFalse(service.updateSpec(context).images.isEmpty, id.rawValue)
        }
    }

    /// The demo fleet shows the shelf to the tour
    func testTheDemoScenarioBServerCarriesTheWholeShelf() throws {
        setenv("GRYONIXNEXUS_DEMO_SERVERS", "4", 1)
        defer { unsetenv("GRYONIXNEXUS_DEMO_SERVERS") }
        let demo = try XCTUnwrap(DemoDeployments.fromEnvironment())
        let home = demo.first { $0.services.contains(.homeAssistant) }
        XCTAssertNotNil(home, "no demo server carries the hub")
        XCTAssertEqual(home?.topology, .vpsRelayWithHomeBackend)
        XCTAssertTrue(home?.services.contains(.mosquitto) ?? false)
        XCTAssertTrue(home?.services.contains(.zigbee2MQTT) ?? false)
        XCTAssertFalse(home?.serviceSettings.homeAssistantUSBDevice.isEmpty ?? true)
    }
}

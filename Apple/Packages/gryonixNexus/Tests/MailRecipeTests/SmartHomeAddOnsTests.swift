import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Mosquitto and Zigbee2MQTT, pinned over the generated artifacts
final class SmartHomeAddOnsTests: XCTestCase {
    private let stick = "/dev/serial/by-id/usb-ITead_Sonoff-if00-port0"

    private func input(_ services: Set<ServiceID>, stick: String? = nil) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            services: services,
            serviceSettings: ServiceSettings(machineAtHome: true,
                                             homeAssistantUSBDevice: stick ?? self.stick)
        )
    }

    private func script(_ services: Set<ServiceID>, stick: String? = nil) throws -> String {
        let bundle = try MailRecipe().generate(from: try input(services, stick: stick))
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    func testAnAddOnAloneIsRefused() throws {
        for addOn in ServiceID.smartHomeAddOns {
            XCTAssertThrowsError(try script([addOn]), addOn.rawValue) { error in
                guard case ValidationError.inconsistentTopology(let message) = error else {
                    return XCTFail("\(addOn.rawValue): \(error)")
                }
                XCTAssertTrue(message.contains("Home Assistant"), message)
            }
        }
    }

    func testZigbeeWithoutAStickIsRefused() throws {
        XCTAssertThrowsError(try script([.homeAssistant, .zigbee2MQTT, .mosquitto], stick: "")) { error in
            guard case ValidationError.inconsistentTopology(let message) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(message.contains("Zigbee"), message)
        }
    }

    /// The radio publishes to the broker, so one brings both
    func testTickingZigbeeBringsTheBroker() {
        let expanded = ServiceRegistry.expanded([.homeAssistant, .zigbee2MQTT],
                                                scope: .publicInternet, modelBackend: .here)
        XCTAssertTrue(expanded.contains(.mosquitto))
    }

    func testTheBrokerRefusesAnonymousClientsAndOpensItsPort() throws {
        let text = try script([.homeAssistant, .mosquitto])
        XCTAssertTrue(text.contains("allow_anonymous false"))
        XCTAssertTrue(text.contains("password_file /mosquitto/config/passwd"))
        XCTAssertTrue(text.contains("\(MosquittoService.brokerPort):1883"))
    }

    /// Both accounts are made inside the image's own container
    func testTheAccountsAreCreatedInTheImage() throws {
        let text = try script([.homeAssistant, .mosquitto])
        for user in MosquittoService.users {
            XCTAssertTrue(text.contains("\(user) \"$MQTT_PASSWORD\""), user)
        }
        XCTAssertTrue(text.contains("mosquitto_passwd -U /mosquitto/config/passwd"))
        XCTAssertTrue(text.contains("docker run --rm -v /opt/mosquitto/config:/mosquitto/config"))
    }

    func testTheBrokerPasswordNeverRidesACommandLine() throws {
        let text = try script([.homeAssistant, .mosquitto])
        XCTAssertFalse(text.contains("mosquitto_passwd -b"))
        XCTAssertTrue(text.contains("printf '%s:%s\\n' homeassistant \"$MQTT_PASSWORD\""))
    }

    func testZigbeeIsHandedTheStickAndTheBrokersPassword() throws {
        let text = try script([.homeAssistant, .mosquitto, .zigbee2MQTT])
        XCTAssertTrue(text.contains("- \(stick):\(stick)"), "the stick reaches the container")
        XCTAssertTrue(text.contains("  port: \(stick)"), "and the settings file names it")
        XCTAssertTrue(text.contains("  user: \(Zigbee2MQTTService.mqttUser)"))
        XCTAssertTrue(text.contains("  password: $MQTT_PASSWORD"))
        XCTAssertTrue(text.contains(". /opt/mosquitto/.env"))
    }

    /// Without a settings file the bridge serves an onboarding page
    func testTheBridgeIsConfiguredRatherThanOnboarded() throws {
        let text = try script([.homeAssistant, .mosquitto, .zigbee2MQTT])
        XCTAssertTrue(text.contains("configuration.yaml <<EOF_Z2M_CONFIG"))
        XCTAssertTrue(text.contains("  host: 127.0.0.1"))
        XCTAssertTrue(text.contains("  port: \(Zigbee2MQTTService.webUIPort)"))
        // Published ports are discarded on the host network
        XCTAssertFalse(text.contains("127.0.0.1:\(Zigbee2MQTTService.webUIPort):8080"))
    }

    /// The broker's password belongs on the screen
    func testTheReportCarriesTheBrokersAccountsAndItsPassword() throws {
        let text = try script([.homeAssistant, .mosquitto])
        XCTAssertTrue(text.contains("\(L10nServices.mosquittoAccountsLabel(.en)): "
                                    + MosquittoService.users.joined(separator: ", ")))
        XCTAssertTrue(text.contains("grep '^MQTT_PASSWORD=' /opt/mosquitto/.env"))
        XCTAssertTrue(text.contains(L10nServices.passwordGeneratedOnServerLabel(.en)))
    }

    /// An add-on is offered only beside a ticked hub
    func testThePickerHidesAnAddOnWithoutTheHub() {
        let withoutHub = ServiceRegistry.services(in: .smartHome, scope: .publicInternet,
                                                  selected: [])
        XCTAssertEqual(withoutHub.map(\.id), [.homeAssistant])

        let withHub = ServiceRegistry.services(in: .smartHome, scope: .publicInternet,
                                               selected: [.homeAssistant])
        XCTAssertEqual(withHub.map(\.id), [.homeAssistant, .mosquitto, .zigbee2MQTT])
    }
}

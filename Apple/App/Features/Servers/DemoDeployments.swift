#if DEBUG
import Foundation
import ServerControl
import ServiceCatalog

/// A synthetic fleet for design work and screenshots
enum DemoDeployments {
    static func fromEnvironment() -> [Deployment]? {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["GRYONIXNEXUS_DEMO_SERVERS"] else { return nil }
        let requested = max(1, Int(raw) ?? slots)
        return (0..<requested).map { index in
            fleet(copy: index / slots)[index % slots]
        }
    }

    private static let slots = 4

    static func isSynthetic(_ deployment: Deployment) -> Bool {
        fromEnvironment()?.contains { $0.id == deployment.id } ?? false
    }

    private static func fleet(copy: Int) -> [Deployment] {
        let mark = copy == 0 ? "" : " #\(copy + 1)"
        func id(_ slot: String) -> UUID {
            UUID(uuidString: String(format: "%08X-0000-0000-0000-0000000000%@", copy, slot))!
        }
        return [
            Deployment(
                id: id("A1"),
                name: "example.net" + mark,
                topology: .singleHost,
                domain: "example.net",
                entry: HostEndpoint(host: "203.0.113.10", user: "server-user"),
                services: [.mailcow, .vaultwarden, .nextcloud, .wireguardVPN, .vpnPanel,
                           .headscale, .tailscaleNode, .minecraftJava, .craftyController,
                           .ollama],
                tags: ["prod"],
                usesAgent: true,
                tintName: ServerTint.teal.rawValue
            ),
            Deployment(
                id: id("B2"),
                name: "b5.example.net" + mark,
                topology: .vpsRelayWithHomeBackend,
                domain: "b5.example.net",
                additionalDomains: ["b6.example.net"],
                entry: HostEndpoint(host: "203.0.113.20", user: "server-user"),
                homeWGAddress: "10.8.0.2",
                services: [.dockerMailserver, .vaultwarden, .wireguardVPN, .vpnPanel,
                           .homeAssistant, .mosquitto, .zigbee2MQTT],
                serviceSettings: ServiceSettings(
                    homeAssistantUSBDevice:
                        "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus-if00-port0"),
                tags: ["prod", "home"],
                tintName: ServerTint.purple.rawValue
            ),
            Deployment(
                id: id("C3"),
                name: "lab.gryonix.com" + mark,
                topology: .singleHost,
                domain: "lab.gryonix.com",
                entry: HostEndpoint(host: "203.0.113.30", user: "server-user"),
                services: [.immich, .forgejo],
                tags: ["lab"],
                tintName: ServerTint.orange.rawValue
            ),
            Deployment(
                id: id("D4"),
                name: "orion" + mark,
                topology: .singleHost,
                domain: "orion.local",
                entry: HostEndpoint(host: "192.168.178.100", user: "admin"),
                services: [.nextcloud],
                tags: ["lab"],
                iconSymbol: "house.fill",
                tintName: ServerTint.green.rawValue
            )
        ]
    }
}
#endif

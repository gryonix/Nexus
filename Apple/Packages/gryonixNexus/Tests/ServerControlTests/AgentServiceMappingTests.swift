import ServiceCatalog
import XCTest
@testable import ServerControl

final class AgentServiceMappingTests: XCTestCase {
    func testEveryCatalogServiceHasAnAgentID() {
        for service in ServiceRegistry.all {
            XCTAssertNotNil(
                AgentServiceMapping.agentID(for: service.id),
                "\(service.id.rawValue) is installable but the agent map has no id for it — "
                    + "its card falls back to SSH and an adopted host does not list it at all"
            )
        }
    }

    func testEveryCatalogServiceRoundTripsThroughTheAgentID() {
        for service in ServiceRegistry.all {
            guard let agentID = AgentServiceMapping.agentID(for: service.id) else { continue }
            let back = AgentServiceMapping.serviceIDs(forAgentIDs: [agentID])
            if service.id == .vpnPanel || ServiceID.vpnProtocols.contains(service.id) {
                XCTAssertEqual(agentID, "vpn", "\(service.id.rawValue) must fold into the aggregate VPN id")
                XCTAssertEqual(back, [.vpnPanel])
            } else {
                XCTAssertEqual(
                    back, [service.id],
                    "\(service.id.rawValue) → \(agentID) → \(back.map(\.rawValue)) does not come back to itself"
                )
            }
        }
    }

    func testPassboltIsMappedInBothDirections() {
        XCTAssertEqual(AgentServiceMapping.agentID(for: .passbolt), "passbolt")
        XCTAssertEqual(AgentServiceMapping.serviceIDs(forAgentIDs: ["passbolt"]), [.passbolt])
    }

    func testUnknownAgentIDsAreDropped() {
        XCTAssertTrue(AgentServiceMapping.serviceIDs(forAgentIDs: ["portainer", "wordpress"]).isEmpty)
        XCTAssertNil(AgentServiceMapping.agentID(for: ServiceID(rawValue: "portainer")))
    }

    // MARK: - The aggregate "vpn" resolved into real protocols

    func testEachEnginesContainerNamesItsProtocol() {
        let cases: [(String, ServiceID)] = [
            ("awgvpn", .amneziaWG),
            ("openvpn", .openVPN),
            ("shadowsocks", .shadowsocks),
            ("xray", .xrayReality)
        ]
        for (container, expected) in cases {
            let ids = AgentServiceMapping.serviceIDs(
                forAgentServices: [(id: "vpn", containerNames: ["vpnpanel", container])])
            XCTAssertTrue(ids.contains(expected),
                          "the container \(container) must name \(expected.rawValue)")
            XCTAssertTrue(ids.contains(.vpnPanel), "the panel is still part of the answer")
            XCTAssertFalse(ids.contains(.wireguardVPN),
                           "an engine beside the panel must not also claim plain WireGuard")
        }
    }

    func testAPanelOnItsOwnIsPlainWireGuard() {
        let ids = AgentServiceMapping.serviceIDs(
            forAgentServices: [(id: "vpn", containerNames: ["vpnpanel"])])
        XCTAssertEqual(ids, [.vpnPanel, .wireguardVPN])
    }

    func testEveryEngineOnTheHostIsNamed() {
        let ids = AgentServiceMapping.serviceIDs(
            forAgentServices: [(id: "vpn",
                                containerNames: ["vpnpanel", "openvpn", "xray"])])
        XCTAssertEqual(ids, [.vpnPanel, .openVPN, .xrayReality])
    }

    func testContainersOfOtherServicesAreNotReadAsProtocols() {
        let ids = AgentServiceMapping.serviceIDs(
            forAgentServices: [(id: "vaultwarden", containerNames: ["openvpn"])])
        XCTAssertEqual(ids, [.vaultwarden])
    }
}

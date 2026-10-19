import AgentControl
import ServerControl
import ServiceCatalog
import AgentClient
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
final class DemoVPNProtocolTests: XCTestCase {
    override func setUp() async throws {
        await DemoAgentState.shared.forgetEverything()
    }

    private var agentServers: [Deployment] {
        DemoServer.deployments().filter { $0.usesAgent && !$0.services.isDisjoint(with: ServiceID.vpnProtocols) }
    }

    @available(macOS 15.0, *)
    private func vpnOperations(_ deployment: Deployment) throws -> AgentVPNClientOperations {
        AgentVPNClientOperations(client: try XCTUnwrap(DemoAgent.client(for: deployment)))
    }

    func testADemoServerRunsSeveralProtocolsSoThePickerIsDrawn() throws {
        let several = agentServers.filter {
            VPNClientProtocols.installed(in: $0.services).count > 1
        }
        XCTAssertFalse(several.isEmpty,
                       "with one protocol per server the protocol picker never appears at all")
    }

    func testTheFleetBetweenThemRunsEveryProtocol() {
        let running = agentServers.reduce(into: Set<ServiceID>()) {
            $0.formUnion(VPNClientProtocols.installed(in: $1.services))
        }
        XCTAssertEqual(running, ServiceID.vpnProtocols)
    }

    func testEveryInstalledProtocolListsDevicesAndAcceptsANewOne() async throws {
        for deployment in agentServers {
            let ops = try vpnOperations(deployment)
            for id in VPNClientProtocols.installed(in: deployment.services) {
                let before = try await ops.list(protocol: id)
                XCTAssertFalse(before.isEmpty,
                               "\(deployment.name)/\(id.rawValue): an empty list reads as a protocol nobody can use")
                _ = try await ops.add(protocol: id, named: "New phone")
                let after = try await ops.list(protocol: id)
                XCTAssertEqual(after.count, before.count + 1,
                               "\(deployment.name)/\(id.rawValue): the addition has to show on the next read")
                XCTAssertTrue(after.contains { $0.name == "New phone" })
            }
        }
    }

    func testTheListFollowsTheProtocolPicker() async throws {
        let server = try XCTUnwrap(agentServers.first {
            VPNClientProtocols.installed(in: $0.services).count > 1
        })
        let ops = try vpnOperations(server)
        let protocols = VPNClientProtocols.installed(in: server.services)
        let lists = try await protocols.asyncMap { try await ops.list(protocol: $0) }
        let names = lists.map { $0.map(\.name) }
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        for (index, list) in names.enumerated() where index > 0 {
            XCTAssertNotEqual(list, names[0],
                              "two protocols showing the same devices reads as a picker that does nothing")
        }
    }

    func testOpenVPNSaysItsProfileIsNotWorthAQRCode() async throws {
        let server = try XCTUnwrap(agentServers.first { $0.services.contains(.openVPN) })
        let ops = try vpnOperations(server)
        let devices = try await ops.list(protocol: .openVPN)
        let device = try XCTUnwrap(devices.first)
        let profile = try await ops.configuration(protocol: .openVPN, clientID: device.id)
        XCTAssertFalse(profile.qrIsUseful)
        XCTAssertTrue(profile.fileName.hasSuffix(".ovpn"))

        let wireGuard = try await ops.configuration(protocol: .wireguardVPN, clientID: "wg-2")
        XCTAssertTrue(wireGuard.qrIsUseful, "a WireGuard profile is a few lines and scans fine")
    }

    func testNoDemoProfileLooksLikeAWorkingOne() async throws {
        for deployment in agentServers {
            let ops = try vpnOperations(deployment)
            for id in VPNClientProtocols.installed(in: deployment.services) {
                let devices = try await ops.list(protocol: id)
                let device = try XCTUnwrap(devices.first)
                let profile = try await ops.configuration(protocol: id, clientID: device.id)
                XCTAssertTrue(profile.text.contains("DEMO-SERVER-PLACEHOLDER"),
                              "\(deployment.name)/\(id.rawValue) hands out something that reads as a real key")
            }
        }
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}

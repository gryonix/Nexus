import Foundation
import ServerControl
import XCTest
@testable import ServerControlSSH

final class RouteTableTests: XCTestCase {
    private let third = UUID(uuidString: "9F2A6C74-6D6E-4C67-9B31-9A0A5D4A1E01")!

    private func settings(with extra: [SSHConnectionSettings.NodeAddress] = []) -> SSHConnectionSettings {
        var settings = SSHConnectionSettings(
            vpsHost: "203.0.113.10", vpsPort: 22, username: "server-user",
            homeHost: "10.8.0.2", homePort: 22, homeLANHost: "192.168.1.5",
            privateKeySeed: Data(repeating: 7, count: 32),
            pinnedVPSHostKey: "ssh-ed25519 AAAAvps", pinnedHomeHostKey: "ssh-ed25519 AAAAhome")
        settings.additionalNodes = extra
        return settings
    }

    private func runner(_ settings: SSHConnectionSettings) -> CitadelCommandRunner {
        CitadelCommandRunner(settings: settings)
    }

    // MARK: - The two shipped machines

    func testTheEntryMachineIsDialledDirectly() async {
        let route = await runner(settings()).route(to: .vps)
        XCTAssertNil(route?.parent)
        XCTAssertEqual(route?.address.host, "203.0.113.10")
        XCTAssertNil(route?.fallback)
    }

    func testTheHomeMachineIsReachedThroughTheEntryMachineAndFallsBackToItsLAN() async {
        let route = await runner(settings()).route(to: .home)
        XCTAssertEqual(route?.parent, .vps)
        XCTAssertEqual(route?.address.host, "10.8.0.2")
        XCTAssertEqual(route?.fallback?.host, "192.168.1.5")
        XCTAssertEqual(route?.fallback?.pin, route?.address.pin)
    }

    // MARK: - A machine that never had a slot

    func testAThirdMachineIsRoutableOnceTheSettingsDescribeIt() async {
        let settings = settings(with: [
            .init(id: third, host: "198.51.100.7", port: 2222, parent: nil,
                  pinnedHostKey: "ssh-ed25519 AAAAthird")
        ])
        let route = await runner(settings).route(to: .node(third))
        XCTAssertNil(route?.parent)
        XCTAssertEqual(route?.address.host, "198.51.100.7")
        XCTAssertEqual(route?.address.port, 2222)
        XCTAssertEqual(route?.address.pin, "ssh-ed25519 AAAAthird")
    }

    func testAThirdMachineCanBeReachedThroughAnother() async {
        let settings = settings(with: [
            .init(id: third, host: "10.8.0.3", parent: .vps)
        ])
        let runner = runner(settings)
        let route = await runner.route(to: .node(third))
        XCTAssertEqual(route?.parent, .vps)
        let children = await runner.children(of: .vps)
        XCTAssertTrue(children.contains(.node(third)))
        XCTAssertTrue(children.contains(.home))
    }

    func testTheRoutableSetGrowsWithTheSettings() async {
        let two = await runner(settings()).routableHosts
        XCTAssertEqual(two, [.vps, .home])
        let three = await runner(settings(with: [.init(id: third, host: "198.51.100.7")])).routableHosts
        XCTAssertEqual(three, [.vps, .home, .node(third)])
    }

    // MARK: - Refusals

    func testAnUndescribedMachineHasNoRouteAtAll() async {
        let route = await runner(settings()).route(to: .node(UUID()))
        XCTAssertNil(route)
    }

    func testAMachineWithNoLocalAddressHasNoFallback() async {
        var bare = settings()
        bare.homeLANHost = nil
        let route = await runner(bare).route(to: .home)
        XCTAssertNil(route?.fallback)
    }

    /// An empty string is not an address
    func testAnEmptyLocalAddressIsNotAFallback() async {
        var blank = settings()
        blank.homeLANHost = ""
        let route = await runner(blank).route(to: .home)
        XCTAssertNil(route?.fallback)
    }
}

final class AdditionalNodeAddressTests: XCTestCase {
    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2", services: [.vaultwarden])
    }

    func testAShippedPairContributesNoRows() {
        let rows = SSHConnectionSettings.additionalNodes(of: pair()) { _ in nil }
        XCTAssertTrue(rows.isEmpty)
    }

    func testAThirdMachineBecomesARowNamingItsParentAsTheTransportDoes() {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        let third = DeploymentNode(id: UUID(), name: "extra",
                                   endpoint: HostEndpoint(host: "10.8.0.3", port: 2222, user: "root"),
                                   capabilities: [.worker], routedThrough: entry.id)
        deployment.storedNodes = deployment.nodes + [third]

        let rows = SSHConnectionSettings.additionalNodes(of: deployment) { host in
            host == .node(third.id) ? "ssh-ed25519 AAAAthird" : nil
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, third.id)
        XCTAssertEqual(rows.first?.host, "10.8.0.3")
        XCTAssertEqual(rows.first?.port, 2222)
        XCTAssertEqual(rows.first?.parent, .vps)
        XCTAssertEqual(rows.first?.pinnedHostKey, "ssh-ed25519 AAAAthird")
    }

    func testAThirdMachineWithNoParentIsDialledDirectly() {
        var deployment = pair()
        let third = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "198.51.100.7", user: "root"),
                                   capabilities: [.ingress, .worker])
        deployment.storedNodes = deployment.nodes + [third]
        let rows = SSHConnectionSettings.additionalNodes(of: deployment) { _ in nil }
        XCTAssertNil(rows.first?.parent)
    }
}

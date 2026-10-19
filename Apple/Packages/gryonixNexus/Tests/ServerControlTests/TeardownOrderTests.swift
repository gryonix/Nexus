import XCTest
@testable import ServerControl

final class TeardownOrderTests: XCTestCase {
    private func single() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.vaultwarden])
    }

    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2",
                   services: [.vaultwarden])
    }

    func testASingleMachineIsJustItself() {
        XCTAssertEqual(single().teardownOrder.map(\.sshHost), [.vps])
    }

    func testTheHomeHalfIsCleanedBeforeTheRelay() {
        XCTAssertEqual(pair().teardownOrder.map(\.sshHost), [.home, .vps])
    }

    func testEveryMachineAppearsExactlyOnce() {
        let order = pair().teardownOrder
        XCTAssertEqual(order.count, pair().nodes.count)
        XCTAssertEqual(Set(order.map(\.id)).count, order.count)
    }

    func testNoMachineIsCleanedAfterItsParent() {
        let order = pair().teardownOrder
        for (index, node) in order.enumerated() {
            guard let parent = node.routedThrough else { continue }
            let parentIndex = order.firstIndex { $0.id == parent }
            XCTAssertNotNil(parentIndex)
            XCTAssertGreaterThan(parentIndex!, index,
                                 "a machine must be cleaned before the one it is reached through")
        }
    }

    func testTwoWorkersBehindOneEntryBothComeFirst() {
        let entry = UUID()
        let nodes = [
            DeploymentNode(id: entry, endpoint: HostEndpoint(host: "203.0.113.10", user: "root"),
                           capabilities: [.ingress], legacySlot: .vps),
            DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "10.8.0.2", user: "root"),
                           capabilities: [.worker], routedThrough: entry, legacySlot: .home),
            DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                           capabilities: [.worker], routedThrough: entry)
        ]
        var deployment = single()
        deployment.storedNodes = nodes

        let order = deployment.teardownOrder
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order.last?.id, entry, "the machine everything is reached through goes last")
    }

    func testACycleStillReturnsEveryMachine() {
        let first = UUID()
        let second = UUID()
        var deployment = single()
        deployment.storedNodes = [
            DeploymentNode(id: first, endpoint: HostEndpoint(host: "a", user: "root"),
                           capabilities: [.worker], routedThrough: second),
            DeploymentNode(id: second, endpoint: HostEndpoint(host: "b", user: "root"),
                           capabilities: [.worker], routedThrough: first)
        ]
        let order = deployment.teardownOrder
        XCTAssertEqual(Set(order.map(\.id)), [first, second])
        XCTAssertEqual(order.count, 2)
    }
}

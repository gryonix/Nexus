import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class AddedMachineDoesNotLookLikeARelayTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
    }

    private func singleHostWithAnAddedWorker() -> (Deployment, DeploymentNode) {
        var deployment = DemoServer.deployment()
        let entry = deployment.derivedNodes[0]
        let extra = DeploymentNode(id: UUID(), name: "Second worker",
                                   endpoint: HostEndpoint(host: "192.168.1.50", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: entry.id)
        deployment.storedNodes = [entry, extra]
        return (deployment, extra)
    }

    private func relayPair() -> Deployment {
        var pair = DemoServer.relayPair()
        pair.usesAgent = true
        return pair
    }

    private func model(_ deployment: Deployment) -> DashboardViewModel {
        DashboardViewModel(deployment: deployment,
                           makeRunner: { DemoCommandRunner(deployment: $0) })
    }

    // MARK: - The button that reconfigures a machine's firewall

    func testAServerWithAnAddedWorkerIsNotOfferedRelayConfiguration() {
        let (deployment, _) = singleHostWithAnAddedWorker()
        XCTAssertTrue(deployment.hasHomeHost,
                      "precondition: the added worker IS routed through the entry machine")
        XCTAssertFalse(deployment.hasRelayIngress,
                       "precondition: nothing here terminates traffic without running services")

        XCTAssertFalse(model(deployment).canProvisionRelay,
                       "this would reconfigure the machine that runs every service as a relay")
    }

    func testARelayPairIsStillOfferedIt() {
        XCTAssertTrue(model(relayPair()).canProvisionRelay)
    }

    // MARK: - Where the install report is filed

    /// A single-host install writes one report under `"single"`
    func testTheEntryMachinesReportKeepsItsNameWhenAWorkerIsAdded() {
        let (deployment, extra) = singleHostWithAnAddedWorker()
        let entry = deployment.nodes[0]

        XCTAssertEqual(DashboardViewModel.installReportKey(for: entry, in: deployment), "single")
        XCTAssertEqual(DashboardViewModel.installReportKey(for: extra, in: deployment),
                       extra.id.uuidString,
                       "a machine with no install history is keyed by itself, not by a slot")
    }

    /// The relay pair keeps the two names its install wrote
    func testTheRelayPairKeepsVpsAndHome() {
        let pair = relayPair()
        let keys = pair.nodes.map { DashboardViewModel.installReportKey(for: $0, in: pair) }
        XCTAssertEqual(keys, ["vps", "home"])
    }

    func testAThirdWorkerBehindARelayIsKeyedByItself() {
        var pair = relayPair()
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: pair.ingressNode?.id)
        pair.storedNodes = pair.derivedNodes + [extra]

        let keys = pair.nodes.map { DashboardViewModel.installReportKey(for: $0, in: pair) }
        XCTAssertEqual(keys, ["vps", "home", extra.id.uuidString])
    }

    // MARK: - Which machines have a wg0

    /// The tunnel belongs to the pair the install created
    func testOnlyTheInstalledPairIsAskedAboutWireGuard() {
        var pair = relayPair()
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: pair.ingressNode?.id)
        pair.storedNodes = pair.derivedNodes + [extra]
        let model = model(pair)

        XCTAssertEqual(pair.nodes.map { model.showsWireGuard($0) }, [true, true, false])
    }

    func testAServerWithNoRelayIsNotAskedAboutWireGuardAtAll() {
        let (deployment, _) = singleHostWithAnAddedWorker()
        let model = model(deployment)
        XCTAssertEqual(deployment.nodes.map { model.showsWireGuard($0) }, [false, false])
    }
}

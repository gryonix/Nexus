import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class ReattachedInstallTests: XCTestCase {
    private func temporaryStore() -> ConfiguratorStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reattach-tests-\(UUID().uuidString)", isDirectory: true)
        return ConfiguratorStore(directory: directory)
    }

    private let deployment = Deployment(
        name: "middle", topology: .singleHost, domain: "example.test",
        entry: HostEndpoint(host: "203.0.113.40", user: "control"),
        services: [.adguardHome])

    func testNoDraftToRebuildFromReturnsNil() async {
        let store = temporaryStore()
        XCTAssertNil(store.configForReinstall(deploymentID: deployment.id),
                     "precondition: the store must not know this deployment")
        let rebuilt = await ReattachedInstall.rebuild(for: deployment, store: store)
        XCTAssertNil(rebuilt, "with no draft there is nothing to regenerate")
    }

    func testAnotherDeploymentsHistoryEntryIsNotUsed() async {
        let store = temporaryStore()
        var other = ConfiguratorDraft(topology: .singleHost)
        other.domain = "other.test"
        other.deploymentID = UUID()
        store.appendToHistory(other)

        XCTAssertNil(store.configForReinstall(deploymentID: deployment.id))
        let rebuilt = await ReattachedInstall.rebuild(for: deployment, store: store)
        XCTAssertNil(rebuilt)
    }
}

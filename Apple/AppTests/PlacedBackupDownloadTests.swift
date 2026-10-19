import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class PlacedBackupDownloadTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
    }

    /// A second worker, and Forgejo placed on it
    private func deploymentWithAPlacedService() -> (Deployment, DeploymentNode) {
        var deployment = DemoServer.sshOnly()
        let extra = DeploymentNode(id: UUID(), name: "Second worker",
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker])
        deployment.storedNodes = deployment.derivedNodes + [extra]
        var placement = ServicePlacement()
        placement[.forgejo] = extra.id
        deployment.placement = placement
        return (deployment, extra)
    }

    private func model(_ deployment: Deployment) -> DashboardViewModel {
        DashboardViewModel(deployment: deployment,
                           makeRunner: { DemoCommandRunner(deployment: $0) })
    }

    func testAPlacedServicesBackupIsDownloadedFromTheMachineThatRunsIt() async throws {
        let (deployment, extra) = deploymentWithAPlacedService()
        let service = try XCTUnwrap(ServiceRegistry.service(.forgejo))

        await model(deployment).runWrapperBackup(service)

        let operation = try XCTUnwrap(RunningOperationsRegistry.shared.presented,
                                      "the backup presents its progress sheet")
        XCTAssertEqual(operation.downloadHost, .node(extra.id),
                       "the archive is on the machine that ran the wrapper, and the path carries no host")
    }

    func testTheEncryptedBackupTargetsThatMachineToo() async throws {
        let (deployment, extra) = deploymentWithAPlacedService()
        let service = try XCTUnwrap(ServiceRegistry.service(.forgejo))

        await model(deployment).runEncryptedBackup(service, passphrase: "not-stored")

        let operation = try XCTUnwrap(RunningOperationsRegistry.shared.presented)
        XCTAssertEqual(operation.downloadHost, .node(extra.id))
    }

    func testAnUnplacedServiceStillComesOffTheDefaultWorker() async throws {
        let (deployment, extra) = deploymentWithAPlacedService()
        let service = try XCTUnwrap(ServiceRegistry.service(.psono))

        await model(deployment).runWrapperBackup(service)

        let operation = try XCTUnwrap(RunningOperationsRegistry.shared.presented)
        XCTAssertEqual(operation.downloadHost, deployment.servicesHost)
        XCTAssertNotEqual(operation.downloadHost, .node(extra.id))
    }

    func testASingleHostNamesItsOnlyMachine() async throws {
        let deployment = DemoServer.sshOnly()
        let service = try XCTUnwrap(ServiceRegistry.service(.psono))

        await model(deployment).runWrapperBackup(service)

        let operation = try XCTUnwrap(RunningOperationsRegistry.shared.presented)
        XCTAssertEqual(operation.downloadHost, .vps)
    }

    func testTheBackupsListAsksTheSameMachineTheBackupVerbsDo() throws {
        let (deployment, extra) = deploymentWithAPlacedService()
        let model = model(deployment)

        XCTAssertEqual(model.backupDownloadHost(for: .forgejo), .node(extra.id))
        XCTAssertEqual(model.backupDownloadHost(for: .psono), deployment.servicesHost)
    }

    /// The share closure is registered at all
    func testTheShareClosureIsRegisteredWithTheOperation() async throws {
        let (deployment, _) = deploymentWithAPlacedService()
        let service = try XCTUnwrap(ServiceRegistry.service(.forgejo))

        await model(deployment).runWrapperBackup(service)

        let operation = try XCTUnwrap(RunningOperationsRegistry.shared.presented)
        XCTAssertNotNil(RunningOperationsRegistry.shared.downloadBackup(for: operation),
                        "the sheet has nothing to hand the share flow")
    }
}

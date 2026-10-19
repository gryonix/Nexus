import gryonixNexusCore
import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class LiveProcessCardTests: XCTestCase {
    // MARK: - Installing a server

    func testTheInstallLineIsTheStageAndNothingElseOnOneMachine() {
        let model = InstallViewModel(deployment: deployment(), bundle: bundle())
        XCTAssertEqual(model.targets.count, 1)
        XCTAssertFalse(model.lockScreenLine.isEmpty,
                       "the card would be blank for the whole start of the run")
        XCTAssertFalse(model.lockScreenLine.contains("1"),
                       "a lone machine was counted: \(model.lockScreenLine)")
    }

    func testTheInstallLineNamesTheMachineWhenThereIsMoreThanOne() {
        let model = InstallViewModel(deployment: relayPair(), bundle: relayPairBundle())
        XCTAssertEqual(model.targets.count, 2)
        let line = model.lockScreenLine
        XCTAssertTrue(line.contains("1") && line.contains("2"),
                      "a two-machine install did not say which machine it is on: \(line)")
    }

    /// The fraction the bar is drawn from
    func testTheInstallReportsAFractionThatStartsAtZeroAndIsDrawable() {
        let model = InstallViewModel(deployment: deployment(), bundle: bundle())
        let fraction = model.overallProgress
        XCTAssertEqual(fraction, 0, accuracy: 0.0001,
                       "an install that has not begun is not part-way through")
        XCTAssertNotNil(OperationPresentation.barValue(
            .init(progressText: "", isFinished: false, progress: fraction)),
                        "the value the install produces is not one the card will draw")
    }

    func testAFailedInstallCanSayWhatWentWrong() {
        let model = InstallViewModel(deployment: deployment(), bundle: bundle())
        XCTAssertNil(model.failureMessage, "an install that has not failed has no failure")
    }

    // MARK: - Installing a service through the agent

    func testARememberedInstallFindsTheNameOfItsMachine() {
        let fleetID = UUID()
        let defaults = testDefaults()
        InstallJobStore(defaults: defaults)
            .remember(deployment: fleetID, service: .nextcloud, jobID: "job-nextcloud-1")

        let pending = PendingAgentInstalls(store: InstallJobStore(defaults: defaults),
                                           fleet: FixedFleet([named("b.example.com", id: fleetID)]))
        XCTAssertEqual(pending.pending.count, 1)
        XCTAssertEqual(pending.pending.first?.serverName, "b.example.com")
        XCTAssertFalse(pending.pending.first?.serviceName.isEmpty ?? true)
    }

    func testARememberedInstallOfADeletedServerStillHasARow() {
        let defaults = testDefaults()
        InstallJobStore(defaults: defaults)
            .remember(deployment: UUID(), service: .vaultwarden, jobID: "job-vaultwarden-1")

        let pending = PendingAgentInstalls(store: InstallJobStore(defaults: defaults),
                                           fleet: FixedFleet([]))
        XCTAssertEqual(pending.pending.count, 1)
        XCTAssertEqual(pending.pending.first?.serverName, "")
    }

    func testAnUnreadableFleetLeavesTheRunOnTheList() {
        let defaults = testDefaults()
        InstallJobStore(defaults: defaults)
            .remember(deployment: UUID(), service: .immich, jobID: "job-immich-1")

        let pending = PendingAgentInstalls(store: InstallJobStore(defaults: defaults),
                                           fleet: FailingFleet())
        XCTAssertEqual(pending.pending.count, 1)
    }

    // MARK: - Fixtures

    private func testDefaults() -> UserDefaults {
        let name = "LiveProcessCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private struct FixedFleet: DeploymentStore, @unchecked Sendable {
        let all: [Deployment]
        init(_ all: [Deployment]) { self.all = all }
        func load() throws -> [Deployment] { all }
        func save(_ deployments: [Deployment]) throws {}
    }

    private struct FailingFleet: DeploymentStore, @unchecked Sendable {
        struct Broken: Error {}
        func load() throws -> [Deployment] { throw Broken() }
        func save(_ deployments: [Deployment]) throws {}
    }

    private func named(_ name: String, id: UUID) -> Deployment {
        Deployment(id: id, name: name, topology: .singleHost, domain: name,
                   entry: HostEndpoint(host: "203.0.113.10", user: "server-user"))
    }

    private func deployment() -> Deployment {
        named("example.com", id: UUID())
    }

    private func relayPair() -> Deployment {
        Deployment(name: "b.example.com",
                   topology: .vpsRelayWithHomeBackend,
                   domain: "b.example.com",
                   entry: HostEndpoint(host: "203.0.113.20", user: "server-user"),
                   homeWGAddress: "10.8.0.2")
    }

    private func script(_ name: String, server: ServerRole) -> Artifact {
        Artifact(fileName: name, kind: .shellScript,
                 contents: "#!/usr/bin/env bash\n# GRYONIXNEXUS_DISTRO: ubuntu\n",
                 summary: "setup", server: server)
    }

    private func bundle() -> GeneratedBundle {
        GeneratedBundle(artifacts: [script("setup.sh", server: .singleHost)])
    }

    private func relayPairBundle() -> GeneratedBundle {
        GeneratedBundle(artifacts: [script("setup-vps.sh", server: .vpsRelay),
                                    script("setup-home.sh", server: .homeBackend)])
    }
}

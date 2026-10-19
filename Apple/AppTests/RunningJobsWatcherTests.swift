import AgentControl
import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class RunningJobsWatcherTests: XCTestCase {
    private func deployment(_ name: String = "vps-middle") -> Deployment {
        Deployment(name: name, topology: .singleHost, domain: "example.test",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"), usesAgent: true)
    }

    private func job(_ kind: AgentJobKind, _ subject: String) -> AgentJob {
        AgentJob(id: "job-1", kind: kind, subject: subject, started: Date(),
                 finished: nil, outcome: .running, failure: "", events: 3)
    }

    func testTheTitleNamesTheVerbAndTheServiceByItsCatalogName() {
        let title = RunningJobsWatcher.title(for: job(.update, "nextcloud"), on: deployment())
        XCTAssertTrue(title.contains("Nextcloud"), "the catalog's name for it, not the agent's id: \(title)")
        XCTAssertFalse(title.contains("nextcloud "), "and not both spellings: \(title)")
        let backup = RunningJobsWatcher.title(for: job(.backup, "nextcloud"), on: deployment())
        XCTAssertNotEqual(title, backup, "an update and a backup of the same service read differently")
    }

    func testEveryWorkerJournalIsRead() {
        var pair = Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.test",
                              entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                              homeWGAddress: "10.8.0.2")
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: pair.ingressNode?.id)
        pair.storedNodes = pair.derivedNodes + [extra]

        XCTAssertEqual(RunningJobsWatcher.journalHosts(of: pair), [.home, .node(extra.id)],
                       "a run on a placed worker journals there and must be read there")
    }

    func testTheRelayIsNotAsked() {
        let pair = Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.test",
                              entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                              homeWGAddress: "10.8.0.2")
        XCTAssertFalse(RunningJobsWatcher.journalHosts(of: pair).contains(.vps),
                       "the relay runs nothing, so it has nothing to narrate")
        XCTAssertEqual(RunningJobsWatcher.journalHosts(of: pair), [.home])
    }

    func testASingleHostIsStillAskedExactlyOnce() {
        XCTAssertEqual(RunningJobsWatcher.journalHosts(of: deployment()), [.vps])
    }

    // MARK: - Titles

    func testAContainerGroupKeepsTheNameTheHostGaveIt() {
        let title = RunningJobsWatcher.title(for: job(.containerBackup, "immich-stack"), on: deployment())
        XCTAssertTrue(title.contains("immich-stack"), title)
    }

    func testAnUnknownKindStillNamesTheServer() {
        let title = RunningJobsWatcher.title(for: job(.unknown, "whatever"), on: deployment("orion"))
        XCTAssertTrue(title.contains("orion"), title)
        XCTAssertFalse(title.isEmpty)
    }

    func testAnAdoptedRunGoesOnTheStripWithoutTakingOverTheScreen() {
        let registry = RunningOperationsRegistry.shared
        registry.presented = nil
        let adopted = LongOperationState(title: "Updating Nextcloud")
        registry.adopt(adopted)
        XCTAssertTrue(registry.entries.contains { $0.id == adopted.id }, "it has to be ON the strip")
        XCTAssertNil(registry.presented, "and it must not open its own sheet")

        let started = LongOperationState(title: "Backing up Nextcloud")
        registry.start(started)
        XCTAssertEqual(registry.presented?.id, started.id)

        registry.presented = nil
        for entry in registry.entries { entry.state.isFinished = true; registry.dismiss(entry.id) }
    }

    func testTheStripPrintsTheHostsWordsAndNotTheProtocol() {
        let tail = """
         Container adguardhome Running
        GRYONIXNEXUS_UPDATE_DONE adguard-home
        GRYONIXNEXUS_UPDATE_CTL_DONE
        """
        let readable = WrapperLogText.readable(tail)
        XCTAssertTrue(readable.contains("Container adguardhome Running"),
                      "the line the owner opened the app for is gone: \(readable)")
        XCTAssertFalse(readable.contains("GRYONIXNEXUS"), "the wiring is still on screen: \(readable)")
    }

    func testAMarkerWithAValueIsAlsoTakenOut() {
        XCTAssertTrue(WrapperLogText.isProtocol("GRYONIXNEXUS_BACKUP_DONE 1877 /opt/backups/x.tar.gz"))
        XCTAssertTrue(WrapperLogText.isProtocol("  GRYONIXNEXUS_UPDATE_CTL_DONE"),
                      "indented by the wrapper is still the protocol")
        XCTAssertFalse(WrapperLogText.isProtocol(" Image adguard/adguardhome:v0.107.78 Pulled "))
    }

    func testTheSameRunIsNotAdoptedTwice() {
        let registry = RunningOperationsRegistry.shared
        let state = LongOperationState(title: "Updating Nextcloud")
        registry.adopt(state)
        registry.adopt(state)
        XCTAssertEqual(registry.entries.filter { $0.id == state.id }.count, 1)
        state.isFinished = true
        registry.dismiss(state.id)
    }

    func testAModelFetchNamesTheModelRatherThanTheEngine() {
        let title = RunningJobsWatcher.title(for: job(.modelPull, "llama3.2:3b"),
                                             on: deployment())
        XCTAssertTrue(title.contains("llama3.2:3b"),
                      "the subject is the model, and the strip has to say which one")
        XCTAssertFalse(title.lowercased().contains("ollama"),
                       "naming the engine would leave somebody guessing which download this is")
    }
}

import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class RebootEveryMachineTests: XCTestCase {
    private func single() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"))
    }

    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "admin"),
                   homeWGAddress: "10.8.0.2")
    }

    private func adding(_ node: DeploymentNode, to deployment: Deployment) -> Deployment {
        var copy = deployment
        copy.storedNodes = deployment.nodes + [node]
        return copy
    }

    private func worker(named name: String = "", at host: String) -> DeploymentNode {
        DeploymentNode(id: UUID(), name: name,
                       endpoint: HostEndpoint(host: host, user: "root"),
                       capabilities: [.worker])
    }

    private func title(_ node: DeploymentNode, _ deployment: Deployment) -> String {
        DashboardViewModel.rebootTitle(for: node, in: deployment)
    }

    // MARK: - What the buttons say

    func testALoneHostIsCalledTheServer() {
        let deployment = single()
        XCTAssertEqual(title(deployment.nodes[0], deployment), "Reboot server")
    }

    /// The shipped pair keeps both of its labels, exactly
    func testTheShippedPairKeepsBothOfItsLabels() {
        let deployment = pair()
        XCTAssertEqual(deployment.nodes.map { title($0, deployment) },
                       ["Reboot VPS", "Reboot local server"])
    }

    /// A machine added later is called by its own name
    func testAnAddedMachineIsCalledByItsName() {
        let extra = worker(named: "Kitchen box", at: "192.168.1.50")
        let deployment = adding(extra, to: pair())
        XCTAssertEqual(title(extra, deployment), "Reboot Kitchen box")
    }

    func testAnUnnamedAddedMachineIsCalledByItsAddress() {
        let extra = worker(at: "192.168.1.50")
        let deployment = adding(extra, to: pair())
        XCTAssertEqual(title(extra, deployment), "Reboot 192.168.1.50")
    }

    func testNoTwoMachinesShareAButtonLabel() {
        var deployment = adding(worker(at: "192.168.1.50"), to: pair())
        deployment = adding(worker(at: "192.168.1.51"), to: deployment)

        let titles = deployment.nodes.map { title($0, deployment) }
        XCTAssertEqual(titles.count, 4)
        XCTAssertEqual(Set(titles).count, titles.count, "two machines answer to one label: \(titles)")
    }

    func testALoneHostOffersExactlyOneRebootButton() {
        XCTAssertEqual(single().nodes.count, 1,
                       "the button list is the node list — one machine, one button")
    }

    // MARK: - What the sshd confirmation asks

    func testTheQuestionSaysHowManyMachinesAreAboutToRestart() {
        XCTAssertEqual(DashboardViewModel(deployment: single(),
                                          makeRunner: { DemoCommandRunner(deployment: $0) })
                        .sshdRestartQuestion, "Restart sshd?")
        XCTAssertEqual(DashboardViewModel(deployment: pair(),
                                          makeRunner: { DemoCommandRunner(deployment: $0) })
                        .sshdRestartQuestion, "Restart sshd on both machines?")

        let three = adding(worker(at: "192.168.1.50"), to: pair())
        XCTAssertEqual(DashboardViewModel(deployment: three,
                                          makeRunner: { DemoCommandRunner(deployment: $0) })
                        .sshdRestartQuestion, "Restart sshd on every machine?",
                       "\"both\" is a count, and it stopped being true")
    }

    func testASingleHostWithAWorkerNoLongerAsksAsIfItWereAlone() {
        let grown = adding(worker(at: "192.168.1.50"), to: single())
        XCTAssertEqual(DashboardViewModel(deployment: grown,
                                          makeRunner: { DemoCommandRunner(deployment: $0) })
                        .sshdRestartQuestion, "Restart sshd on both machines?")
    }

    // MARK: - The words exist in every language

    func testTheNewWordsAreInTheCatalogueInEveryLanguage() throws {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
            .appendingPathComponent("App/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalogue))
        let strings = try XCTUnwrap((json as? [String: Any])?["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 1_000, "read the wrong file — check the path")

        let expected: Set<String> = ["de", "es", "fr", "it", "ja", "ru", "uk", "zh"]
        for key in ["Reboot %@", "Restart sshd on every machine?",
                    "Reboot VPS", "Reboot local server", "Reboot server",
                    "Restart sshd?", "Restart sshd on both machines?"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any],
                                      "\"\(key)\" is not in the catalogue, so eight languages get English")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertTrue(expected.isSubset(of: localizations.keys),
                          "\"\(key)\" is missing \(expected.subtracting(localizations.keys))")
            for (language, unit) in localizations {
                let value = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertFalse((value ?? "").isEmpty, "\"\(key)\" is blank in \(language)")
                if key.contains("%@") {
                    XCTAssertTrue(value?.contains("%@") ?? false,
                                  "\"\(key)\" lost its placeholder in \(language) — the machine's name "
                                  + "would vanish from the button")
                }
            }
        }
    }
}

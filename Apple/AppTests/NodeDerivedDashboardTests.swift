import XCTest

@testable import gryonixNexus

final class NodeDerivedDashboardTests: XCTestCase {
    /// Reading the stored enum off a value
    private let read = ".topology"

    private let generationAndCreationTime: Set<String> = [
        // The configurator: the screens where the shape is chosen.
        "SimpleConfiguratorView.swift",
        "ServiceAdvancedFields.swift",
        "ServiceConfigViewModel.swift",
        "ConfiguratorHistoryView.swift",
        "ScenarioOption.swift",
        "ServerFormView.swift",
        "ReinstallFlowView.swift",
        "ReattachedInstall.swift",
        // The AGENT's own Host.topology field, not a deployment's enum.
        "DemoAgentControl.swift",
        // Routes a scenario choice into the configurator.
        "AppRootView.swift",
        // Stores the drafts, filed by the shape they install.
        "ConfiguratorStore.swift",
        "Deployment.swift"
    ]

    private var appleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
    }

    private var runtimeRoots: [URL] {
        [appleRoot.appendingPathComponent("App"),
         appleRoot.appendingPathComponent("Packages/gryonixNexus/Sources/ServerControl")]
    }

    func testNoScreenThatManagesARunningDeploymentAsksTheTopologyEnum() throws {
        var scanned = 0
        var offenders: [String] = []

        for root in runtimeRoots {
            for file in try swiftFiles(in: root) {
                scanned += 1
                guard !generationAndCreationTime.contains(file.lastPathComponent) else { continue }
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() where line.contains(read) {
                    // Prose about the rule is not a use of it.
                    guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                    offenders.append("\(file.lastPathComponent):\(index + 1)  "
                                     + line.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        XCTAssertGreaterThan(scanned, 100, "the source sweep found almost nothing — check the paths")
        XCTAssertEqual(offenders, [], """
            These ask a two-value enum a question a deployment with three \
            machines cannot answer. Ask the machines instead: isMultiHost, \
            hasRelayIngress, hasHomeHost, servicesHost, host(running:), \
            workerHosts, nodes. If the read really is about the install SHAPE \
            rather than a running deployment, name the file in \
            generationAndCreationTime and say why:
            \(offenders.joined(separator: "\n"))
            """)
    }

    func testTheDerivedQuestionsAreTheOnesInUse() throws {
        var counts: [String: Int] = [:]
        for root in runtimeRoots {
            for file in try swiftFiles(in: root) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for helper in ["isMultiHost", "hasRelayIngress", "hasHomeHost",
                               "servicesHost", "host(running:", "workerHosts"] {
                    counts[helper, default: 0] += source.components(separatedBy: helper).count - 1
                }
            }
        }
        for (helper, count) in counts {
            XCTAssertGreaterThan(count, 0, "\(helper) is declared and called nowhere — a dead seam")
        }
        XCTAssertGreaterThanOrEqual(counts["servicesHost", default: 0], 15,
                                    "far fewer default-host reads than the sweep left behind")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

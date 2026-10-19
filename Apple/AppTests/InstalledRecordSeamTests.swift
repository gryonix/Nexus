import XCTest

@testable import gryonixNexus

final class InstalledRecordSeamTests: XCTestCase {
    private var configurator: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
            .appendingPathComponent("App/Features/ServiceConfig/ServiceConfigViewModel.swift")
    }

    func testTheConfiguratorStoresARecordMergedOntoTheExistingOne() throws {
        let source = try String(contentsOf: configurator, encoding: .utf8)
        XCTAssertTrue(
            source.contains("InstalledDeploymentRecord.merged("),
            """
            The configurator writes the fleet record for a server it may be \
            REINSTALLING, under the id that server already has. Building it \
            from the form alone drops every field the form has no opinion \
            about — the agent flag first — so it must go through \
            InstalledDeploymentRecord.merged(generated:onto:).
            """)
        let merged = source.range(of: "InstalledDeploymentRecord.merged(")
        let stored = source.range(of: "deploymentStore.upsert(")
        let mergedAt = try XCTUnwrap(merged, "no merge in the configurator")
        let storedAt = try XCTUnwrap(stored, "the configurator no longer writes to the fleet")
        XCTAssertTrue(mergedAt.lowerBound < storedAt.lowerBound,
                      "the record is stored before it is merged onto the existing one")
    }
}

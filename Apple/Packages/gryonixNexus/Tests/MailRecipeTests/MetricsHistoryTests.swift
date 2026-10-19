import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

private final class FixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        WireGuardKeyPair(privateKey: "TEST-PRIVATE-KEY=", publicKey: "TEST-PUBLIC-KEY=")
    }
}

final class MetricsHistoryTests: XCTestCase {
    func testDataDirectoryLiteralIsPinned() {
        XCTAssertEqual(MetricsHistorySections.dataDirectory, "/var/lib/gryonixnexus/metrics")
        XCTAssertTrue(MetricsHistorySections.collectorScript
            .contains("DIR=/var/lib/gryonixnexus/metrics"))
    }

    func testCollectorWritesEveryBucketFile() {
        for bucket in MetricsHistorySections.buckets {
            XCTAssertTrue(MetricsHistorySections.collectorScript
                .contains("$DIR/\(bucket.name).csv"),
                "collector never touches \(bucket.name).csv")
        }
    }

    func testEveryHostOfBothScenariosInstallsTheCollector() throws {
        let recipe = MailRecipe(keyProvider: FixedKeyProvider())
        let single = try recipe.generate(from: makeInput(topology: .singleHost))
        let split = try recipe.generate(from: makeInput(topology: .vpsRelayWithHomeBackend))
        let scripts = (single.artifacts + split.artifacts).filter { $0.kind == .shellScript }
        XCTAssertEqual(scripts.count, 3)
        for script in scripts {
            XCTAssertTrue(script.contents.contains("systemctl restart gryonixnexus-metrics"),
                          "\(script.fileName) does not start the collector")
            XCTAssertTrue(script.contents.contains("/opt/gryonixnexus-metrics-collector.sh"),
                          "\(script.fileName) does not install the collector")
        }
    }

    func testCollectorScriptPassesBashSyntaxCheck() throws {
        #if os(macOS)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gryonixnexus-collector-\(UUID().uuidString).sh")
        try MetricsHistorySections.collectorScript.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", tmp.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                               encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "bash -n failed\n\(errorText)")
        #endif
    }

    private func makeInput(topology: Topology) throws -> MailRecipeInput {
        let servers: [ServerNode] = topology == .singleHost
            ? [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                          distribution: .debian)]
            : [ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                          vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
               ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"),
                          distribution: .debian)]
        return MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: topology,
            servers: servers,
            services: [.mailcow],
            language: .en
        )
    }
}

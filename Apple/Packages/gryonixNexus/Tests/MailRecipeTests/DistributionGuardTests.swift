import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

private final class GuardFixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        WireGuardKeyPair(privateKey: "TEST-PRIVATE-KEY=", publicKey: "TEST-PUBLIC-KEY=")
    }
}

/// The distribution guard, checked on the artifact that actually ships
final class DistributionGuardTests: XCTestCase {
    private func makeMixedPairBundle() throws -> GeneratedBundle {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .ubuntu),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"),
                           distribution: .debian)
            ],
            services: [.vaultwarden],
            language: .en
        )
        return try MailRecipe(keyProvider: GuardFixedKeyProvider()).generate(from: input)
    }

    private func script(_ bundle: GeneratedBundle, _ role: ServerRole) throws -> String {
        let artifact = bundle.artifacts.first { $0.kind == .shellScript && $0.server == role }
        return try XCTUnwrap(artifact?.contents, "no script for \(role)")
    }

    func testEachHalfOfAPairIsPinnedToItsOwnDistribution() throws {
        let bundle = try makeMixedPairBundle()
        let relay = try script(bundle, .vpsRelay)
        let home = try script(bundle, .homeBackend)
        XCTAssertTrue(relay.contains("# \(SetupMarkers.distribution): ubuntu"),
                      "the relay script must declare the distribution it was built for")
        XCTAssertTrue(home.contains("# \(SetupMarkers.distribution): debian"),
                      "the home script must declare its own, different distribution")
        XCTAssertTrue(relay.contains(#"if [ "${ID:-}" != "ubuntu" ]"#))
        XCTAssertTrue(home.contains(#"if [ "${ID:-}" != "debian" ]"#))
    }

    func testTheDeclaredDistributionIsReadableFromTheHeader() throws {
        let bundle = try makeMixedPairBundle()
        for (role, expected) in [(ServerRole.vpsRelay, "ubuntu"), (.homeBackend, "debian")] {
            let header = try script(bundle, role).split(separator: "\n").prefix(10)
            let line = header.first { $0.contains("\(SetupMarkers.distribution):") }
            let value = try XCTUnwrap(line?.split(separator: ":").last)
                .trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(value, expected)
        }
    }

    #if os(macOS)
    private func runGuard(_ script: String, id: String, idLike: String?) throws -> Int32 {
        let header = script.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { !$0.hasPrefix("export DEBIAN_FRONTEND") }
            .filter { !$0.contains("id -u") }
            .joined(separator: "\n")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gryonixnexus-distro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let osRelease = dir.appendingPathComponent("os-release")
        var contents = "ID=\(id)\nPRETTY_NAME=\"\(id) test\"\n"
        if let idLike { contents += "ID_LIKE=\"\(idLike)\"\n" }
        try contents.write(to: osRelease, atomically: true, encoding: .utf8)

        let scriptURL = dir.appendingPathComponent("header.sh")
        try header.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.environment = ["GRYONIXNEXUS_OS_RELEASE": osRelease.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testTheGuardAcceptsTheDistributionItWasBuiltFor() throws {
        let home = try script(try makeMixedPairBundle(), .homeBackend)
        XCTAssertEqual(try runGuard(home, id: "debian", idLike: nil), 0)
    }

    func testTheGuardAcceptsADerivativeThroughIDLike() throws {
        let home = try script(try makeMixedPairBundle(), .homeBackend)
        XCTAssertEqual(try runGuard(home, id: "devuan", idLike: "debian"), 0)
        let relay = try script(try makeMixedPairBundle(), .vpsRelay)
        XCTAssertEqual(try runGuard(relay, id: "linuxmint", idLike: "ubuntu debian"), 0)
    }

    /// Ubuntu lists debian in ID_LIKE
    func testTheGuardStillRefusesADistributionWeModelSeparately() throws {
        let home = try script(try makeMixedPairBundle(), .homeBackend)
        XCTAssertNotEqual(try runGuard(home, id: "ubuntu", idLike: "debian"), 0)
    }

    func testTheGuardRefusesAnUnrelatedDistribution() throws {
        let home = try script(try makeMixedPairBundle(), .homeBackend)
        XCTAssertNotEqual(try runGuard(home, id: "fedora", idLike: "rhel"), 0)
    }
    #endif

    func testTheAppSideMatcherAgreesWithTheShellGuard() {
        XCTAssertTrue(DistributionMatch.accepts(expected: "debian", id: "debian", idLike: ""))
        XCTAssertTrue(DistributionMatch.accepts(expected: "debian", id: "devuan", idLike: "debian"))
        XCTAssertTrue(DistributionMatch.accepts(expected: "ubuntu", id: "pop", idLike: "ubuntu debian"))
        XCTAssertFalse(DistributionMatch.accepts(expected: "debian", id: "ubuntu", idLike: "debian"))
        XCTAssertFalse(DistributionMatch.accepts(expected: "debian", id: "fedora", idLike: "rhel"))
        XCTAssertFalse(DistributionMatch.accepts(expected: "ubuntu", id: "debian", idLike: ""))
    }
}

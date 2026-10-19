import VPNProfile
import VPNTunnel
import XCTest
@testable import gryonixNexus

@MainActor
final class PacketTunnelDatapathTests: XCTestCase {
    private func providerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)      // …/Apple/AppTests/<this>
            .deletingLastPathComponent()                 // …/Apple/AppTests
            .deletingLastPathComponent()                 // …/Apple
        let url = root.appendingPathComponent("TunnelExtension/PacketTunnelProvider.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTheProviderKnowsEveryDatapathTheAppCanName() throws {
        let source = try providerSource()

        for datapath in TunnelDatapath.allCases {
            XCTAssertTrue(source.contains("VPNTunnelKeys.\(datapath.rawValue)"),
                          "the extension names no branch for \(datapath.rawValue)")
        }
    }

    /// The two enums, compared as values rather than as text
    func testTheDatapathNamesAreTheSameOnBothSides() {
        XCTAssertEqual(Set(TunnelDatapath.allCases.map(\.rawValue)),
                       [VPNTunnelKeys.wireGuardKit, VPNTunnelKeys.xray, VPNTunnelKeys.openVPN],
                       "a datapath was added on one side only")
    }

    func testTheProviderReadsTheKeyFromTheSharedKeychain() throws {
        let source = try providerSource()
        XCTAssertTrue(source.contains("SharedTunnelSecret.secret("))
        XCTAssertTrue(source.contains("VPNTunnelKeys.configAccount"))
    }

    func testTheSystemConfigurationNamesTheKeyInsteadOfCarryingIt() {
        let stored = SharedTunnelSecret.store("probe")
        let configuration = SystemTunnelEngine.providerConfiguration(
            secret: "[Interface]\nPrivateKey = probe", datapath: .wireGuardKit)
        SharedTunnelSecret.delete()
        if stored {
            XCTAssertNil(configuration[VPNTunnelKeys.config], "the key is in the system's plist")
            XCTAssertEqual(configuration[VPNTunnelKeys.configAccount] as? String,
                           SharedTunnelSecret.activeAccount)
        } else {
            XCTAssertNotNil(configuration[VPNTunnelKeys.config], "no key at all would break the tunnel")
        }
    }

    func testASystemExtensionGetsTheKeyInsideTheConfiguration() {
        let configuration = SystemTunnelEngine.providerConfiguration(
            secret: "[Interface]\nPrivateKey = probe", datapath: .wireGuardKit, inline: true)
        XCTAssertEqual(configuration[VPNTunnelKeys.config] as? String, "[Interface]\nPrivateKey = probe")
        XCTAssertNil(configuration[VPNTunnelKeys.configAccount])
    }

    func testDebugBuildsStartTheAppExtension() {
        XCTAssertFalse(MacTunnelPackaging.usesSystemExtension)
        XCTAssertEqual(MacTunnelPackaging.providers, .appExtensions)
    }

    func testWireGuardAndTheProxiesStartSeparateTunnels() {
        let providers = TunnelProviders.appExtensions
        XCTAssertEqual(providers.bundleID(for: .wireGuardKit), "com.skaymer.gryonixnexus.tunnel")
        XCTAssertEqual(providers.bundleID(for: .xray), "com.skaymer.gryonixnexus.proxytunnel")
        XCTAssertEqual(Set(providers.all).count, 2)
    }

    func testTheSystemExtensionServiceSitsInsideItsAppGroup() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("TunnelExtension/SystemExtension")
        let info = try XCTUnwrap(NSDictionary(contentsOf: folder.appendingPathComponent("Info.plist")))
        let entitlements = try XCTUnwrap(NSDictionary(
            contentsOf: folder.appendingPathComponent("gryonixNexusTunnelSystem.entitlements")))
        let network = try XCTUnwrap(info["NetworkExtension"] as? [String: Any])
        let service = try XCTUnwrap(network["NEMachServiceName"] as? String)
        let groups = try XCTUnwrap(entitlements["com.apple.security.application-groups"] as? [String])
        XCTAssertTrue(groups.contains { service.hasPrefix($0 + ".") }, "macOS refuses the provider")
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "$(PRODUCT_BUNDLE_PACKAGE_TYPE)")
    }

    func testTheConfigurationKeyKeepsTheSpellingAlreadyOnDevices() {
        XCTAssertEqual(VPNTunnelKeys.config, "wgQuickConfig")
    }

    func testEveryCarriedProtocolHasADatapath() {
        for id in TunnelCapableProtocols.all {
            XCTAssertNotNil(TunnelCapableProtocols.datapath(for: id),
                            "\(id.displayName) is offered and has no datapath")
        }
    }
}

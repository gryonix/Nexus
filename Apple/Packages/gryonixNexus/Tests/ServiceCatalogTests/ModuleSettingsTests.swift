import XCTest
@testable import ServiceCatalog

@MainActor
final class ModuleSettingsTests: XCTestCase {
    private func settings() -> ModuleSettings {
        let suite = "modules.tests.\(UUID().uuidString)"
        return ModuleSettings(local: UserDefaults(suiteName: suite)!, cloud: nil)
    }

    func testEveryModuleStartsOff() {
        let modules = settings()
        for module in AppModule.allCases { XCTAssertFalse(modules.isOn(module)) }
        XCTAssertEqual(AppModule.allCases.map(\.rawValue),
                       ["ai", "vpnAdvanced", "portForwarding", "scripts", "dockerAdvanced"])
    }

    func testToggleIsRememberedAndUnknownIDsStayOn() {
        let modules = settings()
        modules.set(.ai, on: true)
        XCTAssertTrue(modules.isOn("ai"))
        XCTAssertTrue(modules.isOn("somethingNew"))
    }

    func testAudioServicesLiveInTheConfiguratorAndOldAudioValueIsIgnored() {
        let suite = "modules.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "modules.audio")
        _ = ModuleSettings(local: defaults, cloud: nil)
        XCTAssertNil(AppModule(rawValue: "audio"))
        let listed = ServiceRegistry.services(in: .audio, scope: .localOnly, selected: []).map(\.id)
        XCTAssertTrue(listed.contains(.shairportSync))
    }

    func testServerSetsDecideWhenKeptOnServers() {
        let suite = "modules.tests.\(UUID().uuidString)"
        let modules = ModuleSettings(local: UserDefaults(suiteName: suite)!, cloud: nil)
        XCTAssertTrue(modules.keptOnServers)
        modules.set(.dockerAdvanced, on: true, server: "a")
        modules.adopt(server: "b", on: ["ai"])
        XCTAssertTrue(modules.isOn(.dockerAdvanced, server: "a"))
        XCTAssertFalse(modules.isOn(.dockerAdvanced, server: "b"))
        XCTAssertTrue(modules.isOn(.ai))
        XCTAssertFalse(modules.isOn(.scripts))
        modules.forget(server: "b")
        XCTAssertFalse(modules.isOn(.ai))
    }

    func testADeviceThatHadModulesOnKeepsThemLocal() {
        let suite = "modules.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: ModuleSettings.key(.ai))
        let modules = ModuleSettings(local: defaults, cloud: nil)
        XCTAssertFalse(modules.keptOnServers)
        XCTAssertTrue(modules.isOn(.ai))
    }
}

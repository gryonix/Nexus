import XCTest
@testable import ServiceCatalog

final class ServiceSettingsAdoptingTests: XCTestCase {
    func testOnlyTheAddedServicesFieldsAreTaken() {
        var stored = ServiceSettings()
        stored.vaultwardenHostname = "vault.example.com"
        stored.forgejoSSHPort = 2222
        var edited = stored
        edited.vaultwardenHostname = "keys.example.com"
        edited.forgejoSSHPort = 3333
        edited.odioHostname = "music.example.com"
        edited.minecraftJavaAcceptsEULA = true

        let merged = stored.adopting(edited, for: [.odio, .minecraftJava])

        XCTAssertEqual(merged.odioHostname, "music.example.com")
        XCTAssertTrue(merged.minecraftJavaAcceptsEULA)
        XCTAssertEqual(merged.vaultwardenHostname, "vault.example.com", "an installed service keeps its address")
        XCTAssertEqual(merged.forgejoSSHPort, 2222)
    }

    func testTheHomeAnswerIsNeverTakenBack() {
        var stored = ServiceSettings()
        stored.machineAtHome = true
        let merged = stored.adopting(ServiceSettings(), for: [.odio])
        XCTAssertTrue(merged.machineAtHome)
        XCTAssertTrue(ServiceSettings().adopting(stored, for: [.odio]).machineAtHome)
    }
}

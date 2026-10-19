import XCTest
@testable import AgentControl
import AgentClient
import ServiceCatalog

final class AgentModOperationsTests: XCTestCase {
    func testVanillaHasNoLoaderAndEveryOtherTypeDoes() {
        XCTAssertNil(AgentModOperations.loader(forFlavour: "VANILLA"))
        XCTAssertNil(AgentModOperations.loader(forFlavour: ""))
        XCTAssertEqual(AgentModOperations.loader(forFlavour: "FABRIC"), "fabric")
        XCTAssertEqual(AgentModOperations.loader(forFlavour: "FORGE"), "forge")
        XCTAssertEqual(AgentModOperations.loader(forFlavour: "PAPER"), "paper")
        XCTAssertEqual(AgentModOperations.loader(forFlavour: "fabric"), "fabric")
    }

    func testTheServerTypeDecidesWhichDirectoryAnUploadGoesIn() {
        XCTAssertEqual(AgentModOperations.slot(forFlavour: "PAPER"), .plugins)
        XCTAssertEqual(AgentModOperations.slot(forFlavour: "SPIGOT"), .plugins)
        XCTAssertEqual(AgentModOperations.slot(forFlavour: "FABRIC"), .mods)
        XCTAssertEqual(AgentModOperations.slot(forFlavour: "FORGE"), .mods)
        XCTAssertEqual(AgentModOperations.slot(forFlavour: "SOMETHING_NEW"), .mods)
    }

    func testAPickedModIsWrittenPinnedToItsVersion() {
        XCTAssertEqual(AgentModOperations.entry(slug: "sodium", versionID: "AANobbMO"), "sodium:AANobbMO")
        XCTAssertEqual(AgentModOperations.entry(slug: "sodium", versionID: ""), "sodium")
    }

    func testTheSettingRoundTripsWithoutEmptyEntries() {
        let entries = AgentModOperations.entries(in: " fabric-api:bQZpGIz0 , ,sodium:AANobbMO,")
        XCTAssertEqual(entries, ["fabric-api:bQZpGIz0", "sodium:AANobbMO"])
        XCTAssertEqual(AgentModOperations.setting(from: entries), "fabric-api:bQZpGIz0,sodium:AANobbMO")
        XCTAssertEqual(AgentModOperations.setting(from: ["", "  "]), "")
        XCTAssertEqual(AgentModOperations.entries(in: ""), [])
    }

    func testTheSlugIsReadBackOutOfAnEntry() {
        XCTAssertEqual(AgentModOperations.slug(ofEntry: "sodium:AANobbMO"), "sodium")
        XCTAssertEqual(AgentModOperations.slug(ofEntry: "sodium"), "sodium")
    }

    func testOnlyTheJavaServerIsAddressed() {
        XCTAssertEqual(AgentModOperations.serviceID, ServiceID.minecraftJava.rawValue)
    }
}

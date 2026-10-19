import XCTest
@testable import ServiceCatalog

/// The table that says where each service's hostname is stored
final class ServiceHostnameSettingsTests: XCTestCase {
    private func context(_ settings: ServiceSettings = ServiceSettings()) -> ServiceContext {
        ServiceContext(domain: "example.com", sshUser: "server-user", settings: settings)
    }

    func testEveryPublishedServiceIsAccountedFor() {
        let context = context()
        for service in ServiceRegistry.all where service.webIngress(context) != nil {
            let named = ServiceSettings.hostnameSettings[service.id] != nil
            let fixed = ServiceSettings.fixedHostnameServices.contains(service.id)
            XCTAssertTrue(named || fixed,
                          "\(service.id.rawValue) is published by Caddy but neither nameable nor listed as fixed")
            XCTAssertFalse(named && fixed,
                           "\(service.id.rawValue) cannot be both nameable and fixed")
        }
    }

    /// A row may not point at somebody else's field
    func testEachEntryDrivesTheServiceItNames() {
        for (id, _) in ServiceSettings.hostnameSettings {
            guard let service = ServiceRegistry.service(id) else {
                return XCTFail("\(id.rawValue) is in the table but not in the catalog")
            }
            var settings = ServiceSettings()
            settings.applyHostnames([id: "chosen.example.org"])
            XCTAssertEqual(service.webIngress(context(settings))?.hostname,
                           "chosen.example.org",
                           "\(id.rawValue)'s table entry names the wrong field")
        }
    }

    func testNamingOneServiceLeavesTheOthersOnTheirDefaults() {
        let defaults = context()
        for (id, _) in ServiceSettings.hostnameSettings {
            var settings = ServiceSettings()
            settings.applyHostnames([id: "chosen.example.org"])
            let changed = context(settings)
            for other in ServiceSettings.hostnameSettings.keys where other != id {
                guard let service = ServiceRegistry.service(other) else { continue }
                XCTAssertEqual(service.webIngress(changed)?.hostname,
                               service.webIngress(defaults)?.hostname,
                               "naming \(id.rawValue) also moved \(other.rawValue)")
            }
        }
    }

    func testValuesAreCleanedTheOneWay() {
        var settings = ServiceSettings()
        settings.applyHostnames([.seafile: "  Files.Example.COM "])
        XCTAssertEqual(settings.seafileHostname, "files.example.com")
    }

    func testBlankNamesAreNotCarriedBack() {
        var settings = ServiceSettings()
        settings.applyHostnames([.seafile: "files.example.com", .psono: "   "])
        XCTAssertEqual(settings.namedHostnames, [.seafile: "files.example.com"])
    }
}

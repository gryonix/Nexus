import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// Names given to services are kept per server
@MainActor
final class ServiceOwnNamesTests: XCTestCase {
    private let suite = "service-own-names-tests"
    private var defaults: UserDefaults!
    private let server = UUID()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAGivenNameReplacesTheCatalogOneOnThatServerOnly() throws {
        let store = ServiceOwnNames(local: defaults)
        let service = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        XCTAssertEqual(store.title(service, server: server), service.displayName)

        store.set("  Passwords ", service: .vaultwarden, server: server.uuidString, sent: true)
        XCTAssertEqual(store.title(service, server: server), "Passwords")
        XCTAssertEqual(store.title(service, server: UUID()), service.displayName)
        XCTAssertEqual(ServiceOwnNames(local: defaults).name(.vaultwarden, server: server), "Passwords",
                       "a new instance reads what was stored")
    }

    func testAnEmptyNamePutsTheCatalogNameBack() {
        let store = ServiceOwnNames(local: defaults)
        store.set("Passwords", service: .vaultwarden, server: server.uuidString, sent: true)
        store.set("   ", service: .vaultwarden, server: server.uuidString, sent: true)
        XCTAssertNil(store.name(.vaultwarden, server: server))
        XCTAssertTrue(store.names(server: server.uuidString).isEmpty)
    }

    func testANameTheAgentDidNotTakeWaitsUntilTheServerAnswers() {
        let store = ServiceOwnNames(local: defaults)
        store.set("Passwords", service: .vaultwarden, server: server.uuidString, sent: false)
        XCTAssertEqual(store.unsent, [server.uuidString])

        store.adopt(server: server.uuidString, names: ["vaultwarden": "Passwords"])
        XCTAssertTrue(store.unsent.isEmpty)
    }

    func testTheServersSetReplacesTheLocalOne() {
        let store = ServiceOwnNames(local: defaults)
        store.set("Old", service: .vaultwarden, server: server.uuidString, sent: true)
        store.adopt(server: server.uuidString, names: ["nextcloud": "Files", "seafile": ""])
        XCTAssertEqual(store.names(server: server.uuidString), ["nextcloud": "Files"])
    }

    func testANameIsOneTrimmedLineOfSixtyCharacters() {
        XCTAssertEqual(ServiceOwnNames.cleaned("  My\nvault  "), "My vault")
        XCTAssertEqual(ServiceOwnNames.cleaned(String(repeating: "я", count: 80)).count, 60)
    }

    func testTheStoredNameIsReadableWithoutTheStore() {
        ServiceOwnNames(local: defaults).set("Passwords", service: .vaultwarden, server: server.uuidString, sent: true)
        XCTAssertEqual(ServiceOwnNames.storedName(service: "vaultwarden", server: server, in: defaults), "Passwords")
        XCTAssertNil(ServiceOwnNames.storedName(service: "nextcloud", server: server, in: defaults))
    }
}

import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class TunnelProfileStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var store: TunnelProfileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "TunnelProfileStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = TunnelProfileStore(fileURL: directory.appendingPathComponent("profiles.json"),
                                   defaults: defaults)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func profile(device: String = "device-1",
                         name: String = "iPhone",
                         server: UUID = UUID(),
                         protocolID: ServiceID = .wireguardVPN,
                         createdAt: Date = Date()) -> TunnelProfile {
        TunnelProfile(serverID: server, serverName: "Home", protocolID: protocolID,
                      deviceID: device, deviceName: name,
                      endpoint: "vpn.example.com:51820", addresses: ["10.9.0.4/32"],
                      createdAt: createdAt)
    }

    func testAnEmptyStoreIsEmptyRatherThanAFailure() {
        XCTAssertEqual(store.load(), [])
        XCTAssertNil(store.selected())
    }

    func testSavedProfilesComeBackNewestFirst() {
        let old = profile(device: "a", createdAt: Date(timeIntervalSince1970: 1_000))
        let new = profile(device: "b", createdAt: Date(timeIntervalSince1970: 2_000))
        store.save(old)
        store.save(new)
        XCTAssertEqual(store.load().map(\.deviceID), ["b", "a"])
    }

    func testReIssuingADeviceReplacesItsProfileAndKeepsTheID() {
        let server = UUID()
        let first = store.save(profile(server: server))
        let again = store.save(profile(name: "iPhone (new keys)", server: server))

        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(again.id, first.id, "a replacement must keep the id a widget is pointing at")
        XCTAssertEqual(store.load().first?.deviceName, "iPhone (new keys)")
    }

    func testTheSameDeviceOnAnotherServerIsASecondProfile() {
        store.save(profile(server: UUID()))
        store.save(profile(server: UUID()))
        XCTAssertEqual(store.load().count, 2)
    }

    /// And on the same server under a different protocol
    func testTheSameDeviceUnderAnotherProtocolIsASecondProfile() {
        let server = UUID()
        store.save(profile(server: server, protocolID: .wireguardVPN))
        store.save(profile(server: server, protocolID: .amneziaWG))
        XCTAssertEqual(store.load().count, 2)
    }

    func testTheFirstProfileBecomesTheSelectionSoTheBigButtonHasSomethingToDo() {
        let saved = store.save(profile())
        XCTAssertEqual(store.selectedID, saved.id)
        XCTAssertEqual(store.selected()?.id, saved.id)
    }

    func testAddingASecondProfileDoesNotStealTheSelection() {
        let first = store.save(profile(device: "a"))
        store.save(profile(device: "b"))
        XCTAssertEqual(store.selectedID, first.id)
    }

    func testRemovingTheSelectedProfileMovesTheSelectionRatherThanLeavingItDangling() {
        let first = store.save(profile(device: "a"))
        let second = store.save(profile(device: "b"))
        store.remove(id: first.id)
        XCTAssertEqual(store.selectedID, second.id)
        XCTAssertEqual(store.load().count, 1)
    }

    func testASelectionThatNoLongerExistsFallsBackToTheNewestProfile() {
        let saved = store.save(profile(device: "a"))
        store.select(UUID())
        XCTAssertEqual(store.selected()?.id, saved.id)
    }

    func testProfilesForAServerAreFoundSoTheirSecretsCanBeErasedWithIt() {
        let server = UUID()
        store.save(profile(device: "a", server: server))
        store.save(profile(device: "b", server: server))
        store.save(profile(device: "c", server: UUID()))
        XCTAssertEqual(store.profiles(forServer: server).count, 2)
    }

    func testAProfileThatCannotBeWrittenThrowsInsteadOfVanishing() {
        let nowhere = directory.appendingPathComponent("missing/profiles.json")
        let blocked = TunnelProfileStore(fileURL: nowhere, defaults: defaults)
        XCTAssertThrowsError(try blocked.store(profile()))
        XCTAssertEqual(blocked.load(), [])
        XCTAssertNil(blocked.selectedID)
    }

    func testTheSecretAccountIsTheTunnelsIdentityNotTheRecords() {
        let server = UUID()
        let first = profile(server: server)
        let second = profile(name: "renamed", server: server)
        XCTAssertEqual(first.secretAccount, second.secretAccount)
        XCTAssertNotEqual(first.secretAccount, profile(server: UUID()).secretAccount)
    }
}

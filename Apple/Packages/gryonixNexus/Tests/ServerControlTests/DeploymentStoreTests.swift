import XCTest
import ServiceCatalog
@testable import ServerControl

/// File-backed deployment list — save/load/delete round trips
final class DeploymentStoreTests: XCTestCase {
    private var fileURL: URL!
    private var store: FileDeploymentStore!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gryonixnexus-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("deployments.json")
        store = FileDeploymentStore(fileURL: fileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeDeployment(name: String = "Server") -> Deployment {
        Deployment(
            name: name,
            topology: .singleHost,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            services: [.mailcow, .vaultwarden]
        )
    }

    func testEmptyStoreLoadsEmptyList() throws {
        XCTAssertEqual(try store.load(), [])
    }

    func testOneUnreadableEntryDoesNotHideTheRestAndSurvivesASave() throws {
        let good = makeDeployment(name: "Good")
        let list = try JSONSerialization.jsonObject(with: DeploymentListCodec.encode([good])) as! [Any]
        let stranger: [String: Any] = ["id": UUID().uuidString, "name": "From a newer build", "topology": "teleporter"]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: list + [stranger]).write(to: fileURL)

        XCTAssertEqual(try store.load().map(\.name), ["Good"])

        var edited = good
        edited.name = "Edited"
        try store.save([edited])
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as! [[String: Any]]
        XCTAssertEqual(raw.count, 2, "the entry this build cannot read is kept in the file")
        XCTAssertTrue(raw.contains { ($0["name"] as? String) == "From a newer build" })
        XCTAssertEqual(try store.load().map(\.name), ["Edited"])
    }

    func testUpdateChangesOneStoredDeployment() throws {
        let one = makeDeployment(name: "One")
        try store.save([one, makeDeployment(name: "Two")])
        XCTAssertTrue(try store.update(id: one.id) { $0.name = "Renamed" })
        XCTAssertEqual(try store.load().map(\.name), ["Renamed", "Two"])
        XCTAssertFalse(try store.update(id: UUID()) { $0.name = "Nobody" })
    }

    func testSaveLoadRoundTrip() throws {
        let deployments = [makeDeployment(name: "A"), makeDeployment(name: "B")]
        try store.save(deployments)
        XCTAssertEqual(try store.load(), deployments)
    }

    func testUpsertAppendsThenReplaces() throws {
        var deployment = makeDeployment(name: "Before")
        try store.upsert(deployment)
        XCTAssertEqual(try store.load().map(\.name), ["Before"])

        deployment.name = "After"
        deployment.services.insert(.nextcloud)
        try store.upsert(deployment)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1, "upsert by an existing id must not duplicate the entry")
        XCTAssertEqual(loaded.first?.name, "After")
        XCTAssertTrue(loaded.first?.services.contains(.nextcloud) ?? false)
    }

    func testRemoveDeletesOnlyTargetDeployment() throws {
        let keep = makeDeployment(name: "Keep")
        let drop = makeDeployment(name: "Drop")
        try store.save([keep, drop])

        try store.remove(id: drop.id)

        XCTAssertEqual(try store.load(), [keep])
    }

    func testCreatesIntermediateDirectories() throws {
        // The Application Support subdirectory may not exist on first launch.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
        try store.save([makeDeployment()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testStoredJSONIsStableForUnknownServiceIDs() throws {
        let future = Deployment(
            name: "Future",
            topology: .singleHost,
            entry: HostEndpoint(host: "203.0.113.9", user: "ops"),
            services: [ServiceID(rawValue: "jellyfin")]
        )
        try store.save([future])
        XCTAssertEqual(try store.load().first?.services, [ServiceID(rawValue: "jellyfin")])
    }
}

import ServiceCatalog
import XCTest

@testable import gryonixNexus

final class InstallJobStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "install-job-store-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func store() -> InstallJobStore { InstallJobStore(defaults: defaults) }

    func testARunSurvivesTheAppBeingClosed() {
        let deployment = UUID()
        store().remember(deployment: deployment, service: .adguardHome, jobID: "job-7")

        let afterRelaunch = InstallJobStore(defaults: defaults)
        let found = afterRelaunch.job(deployment: deployment, service: .adguardHome)
        XCTAssertEqual(found?.jobID, "job-7",
                       "an install started before the app closed must still be findable after it")
    }

    func testASecondInstallOfTheSameServiceReplacesTheFirst() {
        let deployment = UUID()
        let store = store()
        store.remember(deployment: deployment, service: .nextcloud, jobID: "first")
        store.remember(deployment: deployment, service: .nextcloud, jobID: "second")

        XCTAssertEqual(store.jobs(deployment: deployment).count, 1)
        XCTAssertEqual(store.job(deployment: deployment, service: .nextcloud)?.jobID, "second")
    }

    func testRunsAreKeptPerDeployment() {
        let first = UUID()
        let second = UUID()
        let store = store()
        store.remember(deployment: first, service: .jellyfin, jobID: "on-first")
        store.remember(deployment: second, service: .jellyfin, jobID: "on-second")

        XCTAssertEqual(store.job(deployment: first, service: .jellyfin)?.jobID, "on-first")
        XCTAssertEqual(store.job(deployment: second, service: .jellyfin)?.jobID, "on-second")
        XCTAssertEqual(store.jobs(deployment: first).count, 1)
    }

    /// A finished run is forgotten, and only that one
    func testForgettingOneRunLeavesTheOthers() {
        let deployment = UUID()
        let store = store()
        store.remember(deployment: deployment, service: .adguardHome, jobID: "done")
        store.remember(deployment: deployment, service: .vaultwarden, jobID: "still-going")

        store.forget(deployment: deployment, service: .adguardHome)

        XCTAssertNil(store.job(deployment: deployment, service: .adguardHome))
        XCTAssertEqual(store.job(deployment: deployment, service: .vaultwarden)?.jobID,
                       "still-going")
    }

    func testARecordForAnUnknownServiceCanStillBeCleared() {
        let deployment = UUID()
        let store = store()
        store.remember(deployment: deployment,
                       service: ServiceID(rawValue: "something-a-later-build-adds"),
                       jobID: "orphan")
        XCTAssertEqual(store.jobs(deployment: deployment).count, 1)

        store.forget(deployment: deployment, rawService: "something-a-later-build-adds")

        XCTAssertTrue(store.jobs(deployment: deployment).isEmpty,
                      "a record this build cannot name must not be permanent")
    }

    func testRemovingAServerForgetsEveryRunOnIt() {
        let doomed = UUID()
        let kept = UUID()
        let store = store()
        store.remember(deployment: doomed, service: .adguardHome, jobID: "a")
        store.remember(deployment: doomed, service: .jellyfin, jobID: "b")
        store.remember(deployment: kept, service: .jellyfin, jobID: "c")

        store.forgetAll(deployment: doomed)

        XCTAssertTrue(store.jobs(deployment: doomed).isEmpty)
        XCTAssertEqual(store.jobs(deployment: kept).count, 1)
    }
}

final class StoredInstallJobShapeTests: XCTestCase {
    private let onDisk = """
    [{"deploymentID":"6C4F1E38-6E31-4B54-9D0D-2B6E5C7F1A11",\
    "serviceID":"vaultwarden",\
    "jobID":"6a8d86c0-14a7c7-1",\
    "startedAt":776000000.0}]
    """

    func testARecordWrittenInThisShapeStillDecodes() throws {
        let jobs = try JSONDecoder().decode([StoredInstallJob].self,
                                            from: Data(onDisk.utf8))
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].serviceID, "vaultwarden")
        XCTAssertEqual(jobs[0].jobID, "6a8d86c0-14a7c7-1")
        XCTAssertEqual(jobs[0].deploymentID,
                       UUID(uuidString: "6C4F1E38-6E31-4B54-9D0D-2B6E5C7F1A11"))
    }

    func testWhatThisBuildWritesMatchesThatShape() throws {
        let defaults = UserDefaults(suiteName: "shape-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        InstallJobStore(defaults: defaults).remember(
            deployment: UUID(uuidString: "6C4F1E38-6E31-4B54-9D0D-2B6E5C7F1A11")!,
            service: ServiceID(rawValue: "vaultwarden"),
            jobID: "6a8d86c0-14a7c7-1")

        let written = try XCTUnwrap(defaults.data(forKey: InstallJobStore.key))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: written) as? [[String: Any]])
        XCTAssertEqual(Set(object[0].keys), ["deploymentID", "serviceID", "jobID", "startedAt"],
                       "a field added or renamed here breaks every record already on disk")
    }
}

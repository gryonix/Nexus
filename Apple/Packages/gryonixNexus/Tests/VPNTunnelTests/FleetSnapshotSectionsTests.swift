import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class FleetSnapshotSectionsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> FleetSnapshotStore {
        FleetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    }

    // MARK: - Five writers, one file

    func testNoSectionErasesAnother() {
        let store = store()
        let id = UUID()
        let now = Date()
        store.upsertServices(id: id, name: "Home", summary: .init(total: 9, needingAttention: 1, takenAt: now))
        store.upsertSecurity(id: id, name: "Home", summary: .init(isPresent: true, engineRunning: true,
                                                                  bouncerRunning: true, alertsLast24h: 31,
                                                                  localBans: 4, communityBlocklistIPs: 100,
                                                                  takenAt: now))
        store.upsertBackups(id: id, name: "Home", summary: .init(isOn: true, everyDays: 1,
                                                                 servicesCovered: 6, retention: 7, takenAt: now))
        store.upsertUpdates(id: id, name: "Home", summary: .init(waiting: 2, checked: 9,
                                                                 lastRunOnServer: nil, takenAt: now))
        store.upsertMetrics(id: id, name: "Home", reading: .init(cpuPercent: 12, memUsedBytes: 1,
                                                                 memTotalBytes: 2, diskUsedBytes: 1,
                                                                 diskTotalBytes: 4, machineLabel: "Local",
                                                                 takenAt: now))
        store.upsertServer(id: id, name: "Home",
                           protocols: [.init(protocolID: .wireguardVPN, deviceCount: 3, deviceNames: [])],
                           failure: nil)

        let server = store.read()?.servers.first
        XCTAssertEqual(server?.services?.total, 9)
        XCTAssertEqual(server?.security?.alertsLast24h, 31)
        XCTAssertEqual(server?.backups?.servicesCovered, 6)
        XCTAssertEqual(server?.updates?.waiting, 2)
        XCTAssertEqual(server?.metrics?.cpuPercent, 12)
        XCTAssertEqual(server?.protocols.first?.deviceCount, 3)
        XCTAssertEqual(store.read()?.servers.count, 1, "the writers made more than one server")
    }

    // MARK: - The fleet arithmetic

    func testOnlyServersActuallyAskedAboutAreCounted() {
        let store = store()
        let asked = UUID()
        store.upsertServices(id: asked, name: "Asked",
                             summary: .init(total: 4, needingAttention: 1, takenAt: Date()))
        store.upsertServer(id: UUID(), name: "Never asked", protocols: [], failure: nil)

        let snapshot = store.read()!
        XCTAssertEqual(snapshot.servers.count, 2)
        XCTAssertEqual(snapshot.serversWithServiceReadings.count, 1)
        XCTAssertEqual(snapshot.totalServices, 4)
        XCTAssertEqual(snapshot.servicesNeedingAttention, 1)
    }

    func testUnreachableIsCountedApartFromUnhealthy() {
        let store = store()
        store.upsertServer(id: UUID(), name: "Down", protocols: [], failure: "timed out")
        store.upsertServices(id: UUID(), name: "Up",
                             summary: .init(total: 2, needingAttention: 0, takenAt: Date()))
        let snapshot = store.read()!
        XCTAssertEqual(snapshot.unreachableServerCount, 1)
        XCTAssertEqual(snapshot.servicesNeedingAttention, 0)
    }

    func testTheFleetAgeIsTheOldestReadingNotTheNewest() {
        let store = store()
        let old = Date().addingTimeInterval(-3_600)
        let fresh = Date()
        store.upsertServices(id: UUID(), name: "Stale",
                             summary: .init(total: 1, needingAttention: 0, takenAt: old))
        store.upsertServices(id: UUID(), name: "Fresh",
                             summary: .init(total: 1, needingAttention: 0, takenAt: fresh))
        let age = store.read()?.oldestReadingAge
        XCTAssertNotNil(age)
        XCTAssertEqual(age ?? 0, 3_600, accuracy: 30,
                       "the fleet quoted its freshest reading as the age of all of them")
    }

    func testAnEmptySnapshotHasNoAgeRatherThanZero() {
        XCTAssertNil(FleetSnapshot().oldestReadingAge,
                     "an unread fleet reported an age, which reads as 'just now'")
    }

    // MARK: - What "guarding" means

    func testAnEngineWithoutItsBouncerIsNotGuarding() {
        let base = FleetSnapshot.SecuritySummary(isPresent: true, engineRunning: true,
                                                 bouncerRunning: true, alertsLast24h: 0,
                                                 localBans: 0, communityBlocklistIPs: 0,
                                                 takenAt: Date())
        XCTAssertTrue(base.isGuarding)
        var bouncerDown = base; bouncerDown.bouncerRunning = false
        XCTAssertFalse(bouncerDown.isGuarding)
        var engineDown = base; engineDown.engineRunning = false
        XCTAssertFalse(engineDown.isGuarding)
        var absent = base; absent.isPresent = false
        XCTAssertFalse(absent.isGuarding)
    }

    func testEverySectionSurvivesTheFile() {
        let store = store()
        let id = UUID()
        let ran = Date().addingTimeInterval(-7_200)
        store.upsertUpdates(id: id, name: "Home",
                            summary: .init(waiting: 3, checked: 11, lastRunOnServer: ran, takenAt: Date()))
        let back = store.read()?.servers.first?.updates
        XCTAssertEqual(back?.waiting, 3)
        XCTAssertEqual(back?.checked, 11)
        XCTAssertEqual(back?.lastRunOnServer?.timeIntervalSince1970 ?? 0,
                       ran.timeIntervalSince1970, accuracy: 1)
    }
}

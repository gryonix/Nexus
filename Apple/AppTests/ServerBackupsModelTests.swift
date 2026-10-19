import ServerControl
import ServiceCatalog
import XCTest
@testable import gryonixNexus

@MainActor
final class ServerBackupsModelTests: XCTestCase {
    private func server() -> Deployment {
        Deployment(name: "one", topology: .singleHost, entry: HostEndpoint(host: "198.51.100.1", user: "root"))
    }

    private func row(_ server: Deployment, _ name: String) -> FleetBackup {
        FleetBackup(serverID: server.id, serverName: server.name, serviceID: "x", serviceName: "X",
                    entry: BackupEntry(name: name, sizeText: "1", dateText: ""))
    }

    func testAServerThatNeverAnswersIsGivenUpOnAfterTheDeadline() async {
        let one = server()
        let model = ServerBackupsModel(
            dashboard: DashboardViewModel(deployment: one), deadline: .milliseconds(300),
            lister: { _ in
                try? await Task.sleep(for: .seconds(30))
                return ServerBackups()
            })

        let started = Date()
        await model.load()

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.failure?.isEmpty ?? true, "a silent server gives a reason")
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testPartialAnswersStayWhenTheServerGoesSilent() async {
        let one = server()
        let model = ServerBackupsModel(
            dashboard: DashboardViewModel(deployment: one), deadline: .milliseconds(300),
            lister: { progress in
                progress(ServerBackups(rows: [self.row(one, "early.tar.gz")]))
                try? await Task.sleep(for: .seconds(30))
                return ServerBackups()
            })

        await model.load()

        XCTAssertEqual(model.rows.map(\.entry.name), ["early.tar.gz"])
        XCTAssertNotNil(model.failure)
    }

    func testAnAnswerShowsAllRowsAndNoFailure() async {
        let one = server()
        let model = ServerBackupsModel(
            dashboard: DashboardViewModel(deployment: one), deadline: .seconds(5),
            lister: { progress in
                progress(ServerBackups(rows: [self.row(one, "early.tar.gz")]))
                await Task.yield()
                return ServerBackups(rows: [self.row(one, "early.tar.gz"), self.row(one, "late.tar.gz")])
            })

        await model.load()

        XCTAssertEqual(model.rows.count, 2)
        XCTAssertNil(model.failure)
    }

    func testAFailingServerReportsItsOwnReason() async {
        let one = server()
        let model = ServerBackupsModel(
            dashboard: DashboardViewModel(deployment: one), deadline: .seconds(5),
            lister: { _ in ServerBackups(failed: true, reason: "no route to host") })

        await model.load()

        XCTAssertEqual(model.failure, "no route to host")
    }

    // MARK: - Restoring a listed backup

    private func cloud(_ name: String, services: Set<ServiceID> = [.nextcloud]) -> Deployment {
        Deployment(name: name, topology: .singleHost, entry: HostEndpoint(host: "198.51.100.1", user: "root"),
                   services: services)
    }

    private func restoreModel(here: Deployment, fleet: [Deployment]) async -> ServerBackupsModel {
        let dashboard = DashboardViewModel(deployment: here, makeRunner: { DemoCommandRunner(deployment: $0) })
        _ = try? await dashboard.commandSession()
        return ServerBackupsModel(dashboard: dashboard, fleet: { fleet })
    }

    private func cloudBackup(on server: Deployment, drive: String? = nil, size: Int64? = 1_000) -> FleetBackup {
        FleetBackup(serverID: server.id, serverName: server.name, serviceID: "nextcloud", serviceName: "Nextcloud",
                    entry: BackupEntry(name: "nextcloud-1.tar.gz", sizeText: "1 KB", dateText: "", drive: drive,
                                       sizeBytes: size))
    }

    func testABackupCanGoBackHereOrToAnotherServerWithTheSameService() async {
        let here = cloud("orion")
        let other = cloud("draco")
        let without = cloud("vega", services: [])
        let model = await restoreModel(here: here, fleet: [here, without, other])

        XCTAssertTrue(model.canRestore(cloudBackup(on: here)))
        XCTAssertEqual(model.restoreTargets(for: cloudBackup(on: here)).map(\.name), ["orion", "draco"])
    }

    func testACopyOnADriveGoesBackOnlyToItsOwnServer() async {
        let here = cloud("orion")
        let model = await restoreModel(here: here, fleet: [here, cloud("draco")])
        XCTAssertEqual(model.restoreTargets(for: cloudBackup(on: here, drive: "usb1")).map(\.name), ["orion"])
    }

    func testABackupTooLargeToPassThroughTheDeviceIsRefusedBeforeDownloading() async {
        let here = cloud("orion")
        let other = cloud("draco")
        let model = await restoreModel(here: here, fleet: [here, other])
        let huge = cloudBackup(on: here, size: ServerBackupsModel.copyLimit + 1)
        do {
            try await model.restore(huge, on: other, passphrase: nil)
            XCTFail("a backup over the limit is refused")
        } catch {
            XCTAssertFalse(DashboardViewModel.message(for: error).isEmpty)
        }
    }
}

import Foundation
import ServerControl
import ServiceCatalog

/// Which host's speed to test
struct SpeedTestTarget: Hashable {
    let deployment: Deployment
    let host: SSHHostID
}

/// Runs disk and internet tests; data disks need root
@MainActor
final class SpeedTestViewModel: ObservableObject {
    let deployment: Deployment
    let host: SSHHostID
    let history: SpeedTestHistory

    @Published private(set) var locations = [SpeedTest.systemDirectory]
    /// The location being tested; "" for the internet
    @Published private(set) var running: String?
    @Published private(set) var errorMessage: String?

    static let internet = ""

    init(target: SpeedTestTarget, history: SpeedTestHistory? = nil) {
        deployment = target.deployment
        host = target.host
        self.history = history ?? .shared
    }

    var records: [SpeedRecord] { history.records(deployment.id, host) }

    func latest(_ location: String) -> SpeedRecord? {
        records.first { ($0.location ?? Self.internet) == location }
    }

    /// Mounted arrays and cache disks join the system disk
    func loadLocations() async {
        guard !isDemo, let runner = try? await DashboardSessionFactory.makeRunnerDetached(deployment: deployment),
              let probe = try? await runner.run(ServerHardware.probeCommand, on: host, timeout: .seconds(20)),
              let hardware = ServerHardware.parse(probe.stdout) else {
            if isDemo { locations = [SpeedTest.systemDirectory, RaidPlan.mountPoint] }
            return
        }
        let data = hardware.volumes.compactMap(\.mountpoint) + hardware.disks.compactMap(\.dataMount)
        var seen = Set<String>()
        locations = ([SpeedTest.systemDirectory] + data.filter { $0.hasPrefix("/") && $0 != "/" })
            .filter { seen.insert($0).inserted }
    }

    func testInternet() async {
        await measure(Self.internet) { [self] in
            let output = try await self.output(SpeedTest.internetScript, demo: DemoSpeed.internet, root: false)
            if output.contains("nocurl") { throw StoragePreparation.Failure(detail: UIL10n.string("curl is missing on the server.")) }
            guard let result = SpeedTest.parseInternet(output) else {
                throw StoragePreparation.Failure(detail: UIL10n.string("The speed server did not answer."))
            }
            return SpeedRecord(date: .now, location: nil, internet: result)
        }
    }

    func testDisk(_ location: String) async {
        await measure(location) { [self] in
            let script = SpeedTest.diskScript(directory: location)
            let output = try await self.output(script, demo: DemoSpeed.disk,
                                               root: location != SpeedTest.systemDirectory)
            guard let result = SpeedTest.parseDisk(output) else {
                throw StoragePreparation.Failure(detail: UIL10n.string("The disk test gave no numbers."))
            }
            return SpeedRecord(date: .now, location: location, disk: result)
        }
    }

    private func measure(_ location: String, _ test: @escaping () async throws -> SpeedRecord) async {
        guard running == nil else { return }
        running = location
        errorMessage = nil
        let title = location == Self.internet
            ? UIL10n.string("Testing the internet speed")
            : UIL10n.string("Testing the disk speed")
        let island = IslandRun(title: title, serverName: deployment.name,
                               progressText: location == Self.internet ? "" : location)
        defer {
            running = nil
            island.finish(errorMessage == nil ? UIL10n.string("Measured.") : "", error: errorMessage)
        }
        do {
            let record = try await test()
            history.add(record, deployment.id, host)
            objectWillChange.send()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private var isDemo: Bool {
        #if DEBUG
        return DemoFleet.covers(deployment)
        #else
        return false
        #endif
    }
}

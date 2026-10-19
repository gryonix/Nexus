import Foundation
import ServerControl
import ServiceCatalog

/// Sample answers for the demo fleet
enum DemoSpeed {
    static let disk = """
    write 268435456 bytes (268 MB, 256 MiB) copied, 0.438679 s, 612 MB/s
    read 268435456 bytes (268 MB, 256 MiB) copied, 0.435931 s, 616 MB/s
    mode direct
    \(SpeedTest.doneMarker)
    """
    static let internet = "down 113972322 200\nup 72387184 200\nping 0.010621\n\(SpeedTest.doneMarker)\n"
}

extension SpeedTestViewModel {
    /// Runs as the control user, with sudo for data disks
    func output(_ script: String, demo: String, root: Bool) async throws -> String {
        #if DEBUG
        if DemoFleet.covers(deployment) {
            try await Task.sleep(for: .milliseconds(600))
            return demo
        }
        #endif
        let step = StorageStep(title: UIL10n.string("Speed test"), script: script, doneMarker: SpeedTest.doneMarker)
        guard root else {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
            return try await StoragePreparation.output(of: step, runner: runner, host: host, elevated: false)
        }
        if InstallAddressStore.installUser(deploymentID: deployment.id, host: host) == nil || deployment.usesAgent {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
            let account = deployment.nodes.first(where: { $0.sshHost == host })?.endpoint.user ?? deployment.entry.user
            return try await StoragePreparation.output(of: step, runner: runner, host: host, elevated: account != "root")
        }
        let username = InstallAddressStore.installUser(deploymentID: deployment.id, host: host) ?? "root"
        let slot = host
        let deploymentID = deployment.id
        let stored = await Task.detached { InstallCredentialStore(deploymentID: deploymentID).secret(for: slot) }.value
        guard let secret = stored, let endpoint = deployment.nodes.first(where: { $0.sshHost == host })?.endpoint else {
            throw StoragePreparation.Failure(detail: UIL10n.string("Data disks need the root sign-in saved at installation."))
        }
        let runner = try await InstallSessionFactory.makeRunnerDetached(
            deployment: deployment, address: endpoint.host, port: endpoint.port,
            username: username, pinSlot: host, secret: secret)
        defer { Task { await runner.disconnect() } }
        return try await StoragePreparation.output(of: step, runner: runner, elevated: username != "root")
    }
}

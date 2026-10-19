import Foundation
import ServerControl
import ServerControlSSH

enum ServerSessionWarmup {
    private static let started = OnceFlag()

    static func start() {
        guard started.claim() else { return }
        Task.detached(priority: .userInitiated) {
            _ = MetricsCache.shared
            let deployments = (try? FileDeploymentStore().load()) ?? []
            await withTaskGroup(of: Void.self) { group in
                for deployment in deployments where !DemoServer.isDemo(deployment) {
                    group.addTask { await warm(deployment) }
                }
            }
        }
    }

    private static func warm(_ deployment: Deployment) async {
        guard let runner = try? await DashboardSessionFactory
            .makeRunnerDetached(deployment: deployment) as? CitadelCommandRunner else { return }
        _ = try? await runner.sshClient(for: deployment.servicesHost)
    }
}

/// A once-only flag that can be read from any thread
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

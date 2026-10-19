import Foundation
import ServiceCatalog

public struct UninstallOperations: Sendable {
    public enum Event: Sendable, Hashable {
        case hostStarted(SSHHostID)
        case output(String)
        case hostFinished(SSHHostID)
    }

    private let runner: any SSHCommandRunner
    private let deployment: Deployment

    public init(runner: any SSHCommandRunner, deployment: Deployment) {
        self.runner = runner
        self.deployment = deployment
    }

    public var hosts: [SSHHostID] {
        deployment.teardownOrder.map(\.sshHost)
    }

    /// Cleans every host of the deployment
    public func fullCleanup(purge: PurgeOptions,
                            onEvent: @escaping @Sendable (Event) -> Void) async throws {
        for host in hosts {
            onEvent(.hostStarted(host))
            let command = CommandCatalog.Uninstall.fullCleanup(purge: purge)
            let box = OutputBox()
            do {
                try await DetachedJobs.run(command, kind: .uninstall, subject: "all", on: host, runner: runner,
                                           quickTimeout: deployment.timeouts.duration(for: .quick),
                                           runTimeout: deployment.timeouts.duration(for: .long)) { text in
                    box.append(text)
                    onEvent(.output(text))
                }
            } catch {
                guard ANSIStripper.strip(box.text).contains(CommandCatalog.Uninstall.doneMarker) else { throw error }
            }
            let output = ANSIStripper.strip(box.text)
            guard output.contains(CommandCatalog.Uninstall.doneMarker) else {
                throw ServerControlError.commandFailure(command: command, exitCode: nil,
                                                        stderr: OutputTail.tail(output))
            }
            onEvent(.hostFinished(host))
        }
    }
}

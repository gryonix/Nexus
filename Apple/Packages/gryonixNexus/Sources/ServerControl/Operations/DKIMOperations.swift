import Foundation
import ServiceCatalog

public protocol DKIMManaging: Sendable {
    func fetchRecords() async throws -> [DKIMRecord]
}

/// Which implementation a deployment's DKIM re-read goes through
public enum DKIMRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool,
                             hasMailEngine: Bool) -> ServiceControlRoute {
        guard hasMailEngine else { return .ssh }
        return ServiceControlRouting.route(usesAgent: usesAgent,
                                           agentTransportAvailable: agentTransportAvailable)
    }
}

/// The SSH implementation: the existing mailcow-only dump command, unchanged
public struct SSHDKIMOperations: DKIMManaging {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment

    public init(runner: any SSHCommandRunner, deployment: Deployment) {
        self.runner = runner
        self.deployment = deployment
    }

    public func fetchRecords() async throws -> [DKIMRecord] {
        let command = CommandCatalog.Mailcow.dkimDump
        let host = ServiceRegistry.mailEngine(in: deployment.services)
            .map { deployment.host(running: $0) } ?? deployment.servicesHost
        let result = try await runner.run(command, on: host, timeout: .seconds(60))
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command,
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return DKIMRecordParser.parse(result.stdout)
    }
}

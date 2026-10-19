import Foundation
import MailRecipe
import ServerControl
import ServerControlSSH
import AgentClient
import AgentClientSSH

@available(macOS 15.0, *)
enum AgentConnection {
    struct Session {
        let client: AgentClient
        let runner: any SSHCommandRunner
    }

    static func open(deployment: Deployment, shared: Bool = false, host: SSHHostID? = nil) async throws -> Session {
        if let demo = DemoAgent.session(for: deployment) { return demo }
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment,
                                                                          shared: shared)
        let session = Session(client: try await client(deployment: deployment, runner: runner, host: host),
                              runner: runner)
        await TransferClaim.shared.claimIfPending(session: session, deployment: deployment)
        return session
    }

    /// A client for this runner, demo servers included
    static func client(deployment: Deployment, runner: any SSHCommandRunner,
                       host: SSHHostID? = nil) async throws -> AgentClient {
        if let demo = DemoAgent.client(for: deployment) { return demo }
        guard let citadel = runner as? CitadelCommandRunner else {
            throw ServerControlError.notConfigured(
                UIL10n.string("This server is not managed over the panel's own connection."))
        }
        return try await client(deployment: deployment, runner: citadel, host: host)
    }

    /// An agent client on an ALREADY-OPEN session
    static func client(deployment: Deployment, runner: CitadelCommandRunner,
                       host: SSHHostID? = nil) async throws -> AgentClient {
        let target = host ?? deployment.servicesHost
        _ = try await runner.sshClient(for: target)
        let bridge = AgentBootstrapSections.bridgeCommand
        let uid = DeviceIdentity.uid
        var client = AgentClient(transport: RelinkingAgentTransport(
            link: {
                SSHAgentTransport(client: try await runner.sshClient(for: target),
                                  bridgeCommand: bridge, deviceUID: uid)
            },
            isDeadLink: { SSHAgentTransport.isDeadLink($0) },
            dropLink: { await runner.invalidate(target) }))
        let deploymentID = deployment.id
        client.onJobStarted = { jobID in
            Task { @MainActor in LiveActivityJobs.shared.jobStarted(jobID, on: deploymentID) }
        }
        return client
    }
}

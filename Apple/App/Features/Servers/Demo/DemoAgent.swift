import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf

/// Every machine the demo layer answers for
enum DemoFleet {
    static func covers(_ deployment: Deployment) -> Bool {
        if DemoServer.isDemo(deployment) { return true }
        #if DEBUG
        return DemoDeployments.isSynthetic(deployment)
        #else
        return false
        #endif
    }
}

/// The agent a demo server answers with
@available(macOS 15.0, *)
enum DemoAgent {
    /// A client for a demo server, nil otherwise
    static func client(for deployment: Deployment) -> AgentClient? {
        guard DemoFleet.covers(deployment) else { return nil }
        return AgentClient(transport: DemoAgentTransport(deployment: deployment))
    }

    static func session(for deployment: Deployment) -> AgentConnection.Session? {
        guard let client = client(for: deployment) else { return nil }
        return AgentConnection.Session(client: client,
                                       runner: DemoCommandRunner(deployment: deployment))
    }
}

/// Answers the agent's RPCs without a server
struct DemoAgentTransport: AgentTransport {
    let deployment: Deployment

    private var containers: [String] { deployment.installedServices.map { $0.id.rawValue } }

    func unary(path: String, request: Data) async throws -> Data {
        try? await Task.sleep(for: .milliseconds(180))
        let machine = DemoAgentMachine(id: deployment.id, containers: containers,
                                       deployment: deployment)
        guard let answer = try await DemoAgentState.shared.unary(path: path, request: request,
                                                                machine: machine) else {
            throw AgentError.rpc(code: "unimplemented", message: path)
        }
        return answer
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        let machine = DemoAgentMachine(id: deployment.id, containers: containers,
                                       deployment: deployment)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let steps = try await DemoAgentState.shared.stream(path: path,
                                                                       request: request,
                                                                       machine: machine)
                    for step in steps {
                        try? await Task.sleep(for: .milliseconds(step.delay))
                        try Task.checkCancellation()
                        if step.drops { throw AgentError.transport("the demo line dropped") }
                        continuation.yield(step.payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Which demo machine a call is about
struct DemoAgentMachine: Sendable {
    let id: UUID
    let containers: [String]
    let deployment: Deployment
}

/// One message of a streamed answer
struct DemoAgentStep: Sendable {
    let payload: Data
    var delay: Int = 260
    /// The connection breaks here instead of answering
    var drops = false
}

extension SwiftProtobuf.Message {
    /// The bytes the transport hands back
    var demoPayload: Data { (try? serializedBytes()) ?? Data() }

    func demoStep(delay: Int = 260) -> DemoAgentStep {
        DemoAgentStep(payload: demoPayload, delay: delay)
    }
}

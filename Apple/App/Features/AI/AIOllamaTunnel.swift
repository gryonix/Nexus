import AIAssistant
import Foundation
import ServerControl

@MainActor
enum AIOllamaTunnel {
    static let localPort = 21434
    private static var forwards: [UUID: PortForward] = [:]

    static func baseURL(for deployment: Deployment) async throws -> String {
        let forward = forwards[deployment.id] ?? PortForward(
            deploymentID: deployment.id, name: "AI", localPort: localPort,
            remoteHost: "127.0.0.1", remotePort: 11434)
        forwards[deployment.id] = forward
        let manager = PortForwardManager.shared
        if !manager.state(of: forward).isActive {
            await manager.start(forward, on: deployment)
        }
        if case .failed(let reason) = manager.state(of: forward) {
            throw AIChatFailure(message: reason)
        }
        return "http://127.0.0.1:\(localPort)/v1"
    }
}

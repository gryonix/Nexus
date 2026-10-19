import AgentClient
import Foundation
import ServerControl
import VPNTunnel

/// Hands the VPN session's activity token to its server
@MainActor
final class TunnelActivityPush: ObservableObject {
    static let shared = TunnelActivityPush()

    private var watched: (deployment: Deployment, token: String)?

    @Published private(set) var lastNote: String?

    private static let retryDelays: [UInt64] = [0, 2, 5, 10, 20, 40]

    private init() {}

    func tokenArrived(_ token: String, profile: TunnelProfile, since: Date) {
        guard let deployment = Self.deployment(for: profile) else { return }
        if let previous = watched, previous.token != token { stop() }
        watched = (deployment, token)
        send(Self.request(token: token, profile: profile, since: since), to: deployment)
    }

    /// The session ended here: the server forgets the token
    func stop() {
        guard let watched else { return }
        self.watched = nil
        var request = Gryonixnexusd_V1_WatchTunnelActivityRequest()
        request.token = watched.token
        request.stop = true
        send(request, to: watched.deployment)
    }

    static func request(token: String, profile: TunnelProfile,
                        since: Date) -> Gryonixnexusd_V1_WatchTunnelActivityRequest {
        var request = Gryonixnexusd_V1_WatchTunnelActivityRequest()
        request.token = token
        request.protocol = profile.protocolID.rawValue
        request.address = profile.addresses.first ?? ""
        request.startedAt = since.timeIntervalSinceReferenceDate
        return request
    }

    private static func deployment(for profile: TunnelProfile) -> Deployment? {
        let deployments = (try? FileDeploymentStore().load()) ?? []
        return deployments.first { $0.id == profile.serverID && $0.usesAgent }
    }

    private func send(_ request: Gryonixnexusd_V1_WatchTunnelActivityRequest, to deployment: Deployment) {
        Task {
            guard #available(macOS 15.0, *) else { return }
            var lastError: Error?
            for delay in Self.retryDelays {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
                do {
                    let session = try await AgentConnection.open(deployment: deployment, shared: true,
                                                                 host: deployment.vpnHost)
                    _ = try await session.client.watchTunnelActivity(request)
                    lastNote = nil
                    return
                } catch {
                    lastError = error
                }
            }
            guard !request.stop, let lastError else { return }
            lastNote = UIL10n.string("The server could not be told about this session: %@",
                                     DashboardViewModel.message(for: lastError))
        }
    }
}

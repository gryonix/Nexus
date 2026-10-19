#if os(iOS)
import ActivityKit
import Foundation

/// Registers server-started cards and hands over their tokens
@MainActor
final class LiveActivityStarts {
    static let shared = LiveActivityStarts()

    private var listening = false
    private var startToken: String?
    private var following: Set<String> = []
    /// Card tokens waiting for this phone's push token
    private var pending: [(token: String, job: String, server: String)] = []

    func begin() {
        guard !listening else { return }
        listening = true
        LiveActivitySettings.shared.onOperationsChange = { Task { await LiveActivityStarts.shared.register() } }
        if #available(iOS 17.2, *) {
            Task {
                for await data in Activity<OperationActivityAttributes>.pushToStartTokenUpdates {
                    startToken = Self.hex(data)
                    await register()
                }
            }
        }
        Task {
            for await activity in Activity<OperationActivityAttributes>.activityUpdates { follow(activity) }
        }
        Activity<OperationActivityAttributes>.activities.forEach(follow)
    }

    /// Tells every relay which cards may start on this phone
    func register() async {
        guard let startToken, let device = PushRegistration.shared.token else { return }
        let body: [String: Any] = ["start_token": startToken, "off": LiveActivitySettings.shared.refusedKinds]
        for relay in PushRelays.known {
            await Self.put("\(relay)/v1/devices/\(device)/live", body)
        }
        let waiting = pending
        pending = []
        for card in waiting { await handOver(card.token, job: card.job, server: card.server) }
    }

    private func follow(_ activity: Activity<OperationActivityAttributes>) {
        guard let job = activity.attributes.jobID, let server = activity.attributes.serverID,
              following.insert(activity.id).inserted else { return }
        OperationActivities.shared.adoptRemote(activity)
        Task {
            for await data in activity.pushTokenUpdates {
                await handOver(Self.hex(data), job: job, server: server)
            }
        }
    }

    private func handOver(_ token: String, job: String, server: String) async {
        guard let device = PushRegistration.shared.token else {
            pending.append((token, job, server))
            return
        }
        for relay in PushRelays.known {
            await Self.put("\(relay)/v1/devices/\(device)/live/\(server)/\(job)", ["activity_token": token])
        }
    }

    private static func put(_ address: String, _ body: [String: Any]) async {
        guard let url = URL(string: address), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DevicePushProof.secret, forHTTPHeaderField: "x-gryonix-device-secret")
        _ = try? await URLSession.shared.data(for: request)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
#endif

import Foundation
import ServerControl
import ServerControlSSH
#if os(iOS)
import UIKit
#endif

/// Saved port forwards and the ones running now
@MainActor
final class PortForwardManager: ObservableObject {
    static let shared = PortForwardManager()
    private static let defaultsKey = "portForwards.v1"

    @Published private(set) var forwards: [PortForward] = []
    @Published private(set) var states: [UUID: PortForwardState] = [:]
    private var running: [UUID: PortForwarder] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([PortForward].self, from: data) {
            forwards = saved
        }
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
        #endif
    }

    func forwards(for deployment: Deployment) -> [PortForward] {
        PortForwardList.forServer(deployment.id, in: forwards)
    }

    func state(of forward: PortForward) -> PortForwardState { states[forward.id] ?? .stopped }

    func save(_ forward: PortForward) {
        persist(PortForwardList.upserting(forward, into: forwards))
    }

    func delete(_ forward: PortForward) {
        stop(forward)
        persist(PortForwardList.removing(forward.id, from: forwards))
    }

    func start(_ forward: PortForward, on deployment: Deployment) async {
        guard !state(of: forward).isActive else { return }
        states[forward.id] = .starting
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
            guard let ssh = runner as? CitadelCommandRunner else {
                throw ServerControlError.notConfigured("this connection cannot forward ports")
            }
            let forwarder = PortForwarder { try await ssh.sshClient(for: .vps) }
            try await forwarder.start(localPort: forward.localPort, remoteHost: forward.remoteHost,
                                      remotePort: forward.remotePort)
            running[forward.id] = forwarder
            states[forward.id] = .running(connections: 0)
        } catch {
            states[forward.id] = .failed(error.localizedDescription)
        }
    }

    func stop(_ forward: PortForward) {
        guard let forwarder = running.removeValue(forKey: forward.id) else {
            states[forward.id] = .stopped
            return
        }
        states[forward.id] = .stopped
        Task { await forwarder.stop() }
    }

    func stopAll() {
        for forward in forwards where running[forward.id] != nil { stop(forward) }
    }

    func refreshCounts() {
        for (id, forwarder) in running { states[id] = .running(connections: forwarder.connections) }
    }

    private func persist(_ updated: [PortForward]) {
        forwards = updated
        defaults.set(try? JSONEncoder().encode(updated), forKey: Self.defaultsKey)
    }
}

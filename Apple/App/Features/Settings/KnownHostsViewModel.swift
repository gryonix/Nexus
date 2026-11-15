import Foundation
import ServerControl

@MainActor
final class KnownHostsViewModel: ObservableObject {
    @Published private(set) var rows: [KnownHostKey] = []

    func load(_ deployments: [Deployment]) {
        rows = deployments.flatMap { Self.rows(for: $0) }
    }

    static func rows(for deployment: Deployment) -> [KnownHostKey] {
        let pins = HostKeyPinStore(deploymentID: deployment.id)
        return KnownHosts.entries(for: deployment) { pins.pin(for: $0) }
            + KnownHosts.bastionEntries(for: deployment, endpoints: pins.bastionEndpoints()) {
                pins.pin(forBastion: $0)
            }
    }

    func forget(_ row: KnownHostKey, in deployments: [Deployment]) {
        guard let deployment = deployments.first(where: { row.id.hasPrefix($0.id.uuidString) }) else { return }
        let pins = HostKeyPinStore(deploymentID: deployment.id)
        switch row.owner {
        case .node(let host): pins.reset(host)
        case .bastion(let endpoint): pins.resetBastion(endpoint)
        }
        load(deployments)
    }
}

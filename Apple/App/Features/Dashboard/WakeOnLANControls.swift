import ServerControl
import ServiceCatalog
import SwiftUI
import gryonixNexusCore

enum WakeOnLANAvailability {
    static func isOffered(for deployment: Deployment) -> Bool {
        target(in: deployment) != nil
    }

    static func target(in deployment: Deployment) -> DeploymentNode? {
        if let home = deployment.nodes.first(where: { $0.legacySlot == .home }) { return home }
        if HomePlacement.impliesHome(deployment.scope) || deployment.serviceSettings.machineAtHome {
            return deployment.nodes.first { $0.runsServices } ?? deployment.nodes.first
        }
        return deployment.nodes.first { WakeOnLAN.isLocalNetwork($0.endpoint.host) }
    }
}

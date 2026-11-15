import Foundation
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    /// Installs the service under a new address and moves DNS
    func moveSite(_ service: any ManagedService, to host: String) async -> (Deployment?, [String]) {
        guard let path = ServiceSettings.hostnameSettings[service.id] else { return (nil, []) }
        let before = deployment
        var changed = deployment
        changed.serviceSettings[keyPath: path] = host
        replaceDeployment(changed)
        guard let updated = await installService(service) else {
            replaceDeployment(before)
            return (nil, [])
        }
        return (updated, await ServiceDNSPublisher.move(service, from: before, to: updated))
    }
}

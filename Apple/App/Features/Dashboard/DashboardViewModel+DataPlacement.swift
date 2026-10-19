import Foundation
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    /// Mounted arrays a service can keep its data on
    func dataArrays() async -> [StorageArray] {
        #if DEBUG
        if DemoFleet.covers(deployment) {
            return ServerHardware.parse(DemoHardware.mountedArrayProbe)
                .map(StorageArray.all(in:))?.filter(Self.holdsData) ?? []
        }
        #endif
        do {
            let runner = try await commandSession()
            let result = try await runner.run(ServerHardware.probeCommand, on: deployment.servicesHost,
                                              timeout: .seconds(20))
            return ServerHardware.parse(result.stdout).map(StorageArray.all(in:))?.filter(Self.holdsData) ?? []
        } catch {
            return []
        }
    }

    /// Running, mounted, and not the cache mirror
    nonisolated static func holdsData(_ array: StorageArray) -> Bool {
        guard array.mountpoint?.isEmpty == false, !array.isCacheMirror else { return false }
        switch array.state {
        case .stopped, .unknown: return false
        case .clean, .degraded, .rebuilding, .checking: return true
        }
    }

    /// Points the chosen services' folders at the array
    func placeData(of services: [any ManagedService], under mount: String) -> Deployment {
        var updated = deployment
        for service in services {
            updated.serviceSettings.placeData(of: service.id, under: mount)
        }
        applyDeployment(updated)
        return updated
    }
}

import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

/// Demo servers' open app APIs, kept in memory
actor DemoOpenAPI {
    static let shared = DemoOpenAPI()

    private var chosen: [UUID: [String: [String]]] = [:]

    /// Open by default where the site opens them today
    private static let openByDefault: Set<ServiceID> = [.vaultwarden, .mailcow, .n8n]

    func state(of machine: DemoAgentMachine) -> Gryonixnexusd_V1_OpenAPIState {
        var answer = Gryonixnexusd_V1_OpenAPIState()
        for id in machine.deployment.services.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard !ServiceAPIGroups.groups(for: id).isEmpty else { continue }
            var site = Gryonixnexusd_V1_OpenAPISite()
            site.serviceID = id.rawValue
            site.paths = chosen[machine.id]?[id.rawValue] ?? Self.defaultPaths(of: id)
            site.editable = true
            answer.sites.append(site)
        }
        return answer
    }

    func set(_ request: Gryonixnexusd_V1_SetOpenAPIRequest, on machine: DemoAgentMachine) -> Gryonixnexusd_V1_OpenAPIState {
        chosen[machine.id, default: [:]][request.serviceID] = request.paths
        return state(of: machine)
    }

    private static func defaultPaths(of id: ServiceID) -> [String] {
        openByDefault.contains(id) ? ServiceAPIGroups.groups(for: id).flatMap(\.paths) : []
    }
}

import AgentControl
import Foundation
import ServiceCatalog

/// The install plan an agent runs for this server
enum AgentPlanRecord {
    struct Stored: Codable {
        let planID: String
        /// Each step: the service, then its fellow VPN protocols
        let steps: [[String]]
        var purpose: AgentPlanPurpose?
    }

    private static func key(_ deployment: UUID) -> String { "agentPlan.\(deployment.uuidString)" }

    static func remember(planID: String, steps: [ServiceInstallPlan.Step], deployment: UUID,
                         purpose: AgentPlanPurpose = .add, defaults: UserDefaults = .standard) {
        let stored = Stored(planID: planID, steps: steps.map { step in
            [step.service.id.rawValue] + step.alsoProtocols.map(\.rawValue).sorted()
        }, purpose: purpose)
        defaults.set(try? JSONEncoder().encode(stored), forKey: key(deployment))
    }

    static func stored(deployment: UUID, defaults: UserDefaults = .standard)
        -> (planID: String, steps: [ServiceInstallPlan.Step], purpose: AgentPlanPurpose)? {
        guard let data = defaults.data(forKey: key(deployment)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        let steps = stored.steps.compactMap { ids -> ServiceInstallPlan.Step? in
            guard let first = ids.first, let service = ServiceRegistry.service(ServiceID(rawValue: first)) else { return nil }
            return ServiceInstallPlan.Step(service: service, alsoProtocols: Set(ids.dropFirst().map(ServiceID.init)))
        }
        return (stored.planID, steps, stored.purpose ?? .add)
    }

    static func forget(deployment: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(deployment))
    }
}

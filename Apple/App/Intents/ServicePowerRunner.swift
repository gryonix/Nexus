import Foundation
import ServerControl

struct IntentFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs a service power action on the dashboard's route
@MainActor
enum ServicePowerRunner {
    static func run(_ action: ServicePowerAction, on entity: ServiceEntity,
                    deployments: [Deployment] = IntentFleet.loadDeployments(),
                    makeModel: ((Deployment) -> DashboardViewModel)? = nil)
        async throws -> String {
        guard let (deployment, service) = ServiceEntity.resolve(entity, in: deployments) else {
            throw IntentFailure(message: UIL10n.string("This service is no longer on the server."))
        }
        let model = makeModel?(deployment) ?? DashboardViewModel(deployment: deployment)
        switch action {
        case .start: await model.start(service)
        case .stop: await model.stop(service)
        case .restart: await model.restart(service)
        }
        guard let result = model.quickActionResult else {
            throw IntentFailure(message: UIL10n.string("The server did not answer."))
        }
        if result.isError { throw IntentFailure(message: result.message) }
        return result.message
    }
}

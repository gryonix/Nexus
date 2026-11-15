import AppIntents
import Foundation
import ServerControl
import ServiceCatalog

/// Where the intents read the user's servers from
enum IntentFleet {
    nonisolated(unsafe) static var loadDeployments: () -> [Deployment] = {
        ((try? FileDeploymentStore().load()) ?? []).filter { !DemoServer.isDemo($0) }
    }
}

struct ServerEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Server" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery: ServerEntityQuery { ServerEntityQuery() }

    static func all(in deployments: [Deployment]) -> [ServerEntity] {
        deployments.map { ServerEntity(id: $0.id, name: $0.name) }
    }
}

struct ServerEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ServerEntity] {
        ServerEntity.all(in: IntentFleet.loadDeployments()).filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ServerEntity] {
        ServerEntity.all(in: IntentFleet.loadDeployments())
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        ServerEntity.all(in: IntentFleet.loadDeployments())
    }
}

struct ServiceEntity: AppEntity {
    let id: String
    let serverID: UUID
    let serviceID: String
    let name: String
    let serverName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Service" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(serverName)")
    }
    static var defaultQuery: ServiceEntityQuery { ServiceEntityQuery() }

    static func makeID(server: UUID, service: String) -> String { "\(server.uuidString)/\(service)" }

    /// The given name of a service, or the catalog one
    static func name(of service: any ManagedService, on deployment: Deployment) -> String {
        ServiceOwnNames.storedName(service: service.id.rawValue, server: deployment.id) ?? service.displayName
    }

    static func all(in deployments: [Deployment]) -> [ServiceEntity] {
        deployments.flatMap { deployment in
            deployment.installedServices.map { service in
                ServiceEntity(id: makeID(server: deployment.id, service: service.id.rawValue),
                              serverID: deployment.id, serviceID: service.id.rawValue,
                              name: Self.name(of: service, on: deployment), serverName: deployment.name)
            }
        }
    }

    static func resolve(_ entity: ServiceEntity,
                        in deployments: [Deployment]) -> (Deployment, any ManagedService)? {
        guard let deployment = deployments.first(where: { $0.id == entity.serverID }),
              let service = deployment.installedServices.first(where: { $0.id.rawValue == entity.serviceID })
        else { return nil }
        return (deployment, service)
    }
}

struct ServiceEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ServiceEntity] {
        ServiceEntity.all(in: IntentFleet.loadDeployments()).filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ServiceEntity] {
        ServiceEntity.all(in: IntentFleet.loadDeployments()).filter {
            $0.name.localizedCaseInsensitiveContains(string)
                || $0.serverName.localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [ServiceEntity] {
        ServiceEntity.all(in: IntentFleet.loadDeployments())
    }
}

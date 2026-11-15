import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

/// Which app APIs of a server answer without the VPN
@MainActor
final class OpenAPIModel: ObservableObject {
    @Published private(set) var sites: Loadable<[String: OpenAPISite]> = .idle
    @Published private(set) var busy: Set<ServiceID> = []
    @Published var failure: String?

    private let agent: () async throws -> AgentOpenAPI

    init(agent: @escaping () async throws -> AgentOpenAPI) {
        self.agent = agent
    }

    /// Installed services that offer an API
    static func services(in deployment: Deployment) -> [ServiceID] {
        deployment.installedServices.map(\.id).filter { !ServiceAPIGroups.groups(for: $0).isEmpty }
    }

    func site(_ id: ServiceID) -> OpenAPISite? {
        sites.value?[id.rawValue]
    }

    func isOpen(_ group: ServiceAPIGroup, of id: ServiceID) -> Bool {
        ServiceAPIGroups.openGroups(of: id, openPaths: site(id)?.paths ?? []).contains(group.id)
    }

    func canChange(_ id: ServiceID) -> Bool {
        site(id)?.editable == true && !busy.contains(id)
    }

    func refresh() async {
        if sites.value == nil { sites = .loading }
        do {
            sites = .loaded(try await agent().sites())
        } catch {
            sites = .failed(DashboardViewModel.message(for: error))
        }
    }

    func set(_ group: ServiceAPIGroup, of id: ServiceID, open: Bool) async {
        var groups = ServiceAPIGroups.openGroups(of: id, openPaths: site(id)?.paths ?? [])
        if open { groups.insert(group.id) } else { groups.remove(group.id) }
        await apply(id, groups: groups)
    }

    /// Opens or closes every API of these services
    func setAll(open: Bool, services: [ServiceID]) async {
        for id in services where site(id)?.editable == true {
            await apply(id, groups: open ? Set(ServiceAPIGroups.groups(for: id).map(\.id)) : [])
        }
    }

    /// True all open, false all closed, else nil
    func allOpen(services: [ServiceID]) -> Bool? {
        let states = services.filter { site($0)?.editable == true }.flatMap { id in
            ServiceAPIGroups.groups(for: id).map { isOpen($0, of: id) }
        }
        guard let first = states.first else { return nil }
        return states.allSatisfy { $0 == first } ? first : nil
    }

    private func apply(_ id: ServiceID, groups: Set<String>) async {
        let paths = ServiceAPIGroups.paths(of: id, openGroups: groups, keeping: site(id)?.paths ?? [])
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            sites = .loaded(try await agent().set(serviceID: id.rawValue, paths: paths))
            failure = nil
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }
}

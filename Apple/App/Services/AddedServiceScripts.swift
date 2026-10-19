import gryonixNexusCore
import MailRecipe
import ServerControl
import ServiceCatalog

/// Install scripts for services added to a running server
enum AddedServiceScripts {
    static func scripts(for services: [any ManagedService], on deployment: Deployment) -> [Artifact] {
        var wanted = Set(services.map(\.id))
        if !wanted.isDisjoint(with: ServiceID.vpnProtocols) { wanted.insert(.vpnPanel) }
        guard let bundle = bundle(for: deployment, adding: wanted, keepInstalled: true)
                ?? bundle(for: deployment, adding: wanted, keepInstalled: false) else { return [] }
        let names = Set(wanted.map { "service-\($0.rawValue).sh" })
        return bundle.serviceScripts.filter { names.contains($0.fileName) }
    }

    /// The setup bundle; without installed services when those fail checks
    private static func bundle(for deployment: Deployment, adding wanted: Set<ServiceID>,
                               keepInstalled: Bool) -> GeneratedBundle? {
        var planned = deployment
        planned.services = keepInstalled ? deployment.services.union(wanted) : wanted
        let draft = ConfiguratorDraft(
            reinstalling: planned,
            saved: ConfiguratorStore.shared.configForReinstall(deploymentID: planned.id))
        guard let input = try? draft.makeMailRecipeInput() else { return nil }
        return try? MailRecipe().generate(from: input)
    }
}

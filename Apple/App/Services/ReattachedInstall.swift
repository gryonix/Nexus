import Foundation
import gryonixNexusCore
import MailRecipe
import ServerControl

@MainActor
enum ReattachedInstall {
    static func rebuild(for deployment: Deployment,
                        store: ConfiguratorStore = .shared) async
        -> (bundle: GeneratedBundle, openPorts: [OpenPortRequirement])? {
        guard let saved = store.configForReinstall(deploymentID: deployment.id) else { return nil }
        let draft = ConfiguratorDraft(reinstalling: deployment, saved: saved)
        let viewModel = ServiceConfigViewModel(topology: draft.topology,
                                               configuratorStore: store,
                                               restoringConfig: draft)
        await viewModel.prefillStoredPassword()
        await viewModel.generate(persisting: false)
        guard let bundle = viewModel.bundle else { return nil }
        return (bundle, viewModel.openPorts)
    }
}
